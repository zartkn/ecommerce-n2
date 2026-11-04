using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using MsPagamento.Data;
using MsPagamento.Domain;
using MsPagamento.Infra;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;

namespace MsPagamento.Messaging;

/// <summary>
/// Consome pedido.criado, decide o pagamento, salva no MySQL e publica
/// pagamento.aprovado ou pagamento.recusado (CONTRATOS.md, seção 5).
/// </summary>
public sealed class PedidoCriadoConsumer(
    RabbitMqConexao rabbit,
    IServiceScopeFactory scopeFactory,
    Config cfg) : BackgroundService
{
    private IModel? _canalConsumo;
    private IModel? _canalPublicacao;
    private readonly object _lockPublicacao = new();

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            var conexao = rabbit.Conexao;

            // Canal de consumo: exchange, fila e binding com os parâmetros exatos da seção 7
            _canalConsumo = conexao.CreateModel();
            DeclararExchange(_canalConsumo);
            _canalConsumo.QueueDeclare(
                queue: Config.FilaConsumo, durable: true, exclusive: false, autoDelete: false, arguments: null);
            _canalConsumo.QueueBind(
                queue: Config.FilaConsumo, exchange: cfg.Exchange, routingKey: Config.BindingConsumo, arguments: null);
            _canalConsumo.BasicQos(prefetchSize: 0, prefetchCount: 1, global: false);

            // Canal de publicação separado, com confirmação do broker
            _canalPublicacao = conexao.CreateModel();
            DeclararExchange(_canalPublicacao);
            _canalPublicacao.ConfirmSelect();

            var consumer = new AsyncEventingBasicConsumer(_canalConsumo);
            consumer.Received += ProcessarAsync;
            _canalConsumo.BasicConsume(queue: Config.FilaConsumo, autoAck: false, consumer: consumer);

            Log.Info($"consumidor iniciado fila={Config.FilaConsumo} binding={Config.BindingConsumo}");
        }
        catch (Exception e)
        {
            // Sem consumidor o serviço não tem função: encerra com código 1 e o Kubernetes reinicia
            Log.Error($"falha ao iniciar consumidor detalhe=\"{e.Message}\"");
            Environment.ExitCode = 1;
            throw;
        }

        return Task.CompletedTask;
    }

    private void DeclararExchange(IModel canal) =>
        canal.ExchangeDeclare(
            exchange: cfg.Exchange, type: ExchangeType.Topic, durable: true, autoDelete: false, arguments: null);

    private async Task ProcessarAsync(object sender, BasicDeliverEventArgs ea)
    {
        var canal = _canalConsumo!;
        // Copia o corpo: o buffer do RabbitMQ.Client só vale durante o handler
        var corpo = ea.Body.ToArray();

        // 0. Lê e valida o envelope. Inválido: descarta (seção 7.7)
        Envelope<PedidoCriadoDados>? envelope;
        try
        {
            envelope = JsonSerializer.Deserialize<Envelope<PedidoCriadoDados>>(corpo, Json.Opcoes);
            var d = envelope?.Dados;
            if (envelope is null || string.IsNullOrWhiteSpace(envelope.EventId) || d is null ||
                string.IsNullOrWhiteSpace(d.PedidoId) || string.IsNullOrWhiteSpace(d.EmailCliente) ||
                d.ValorTotalCentavos <= 0)
            {
                throw new FormatException("campos obrigatorios ausentes ou invalidos");
            }
        }
        catch (Exception e)
        {
            Log.Error($"mensagem invalida descartada detalhe=\"{e.Message}\"");
            canal.BasicNack(ea.DeliveryTag, multiple: false, requeue: false);
            return;
        }

        var dados = envelope!.Dados;
        Log.Info($"evento recebido tipo={RoutingKeys.PedidoCriado} eventId={envelope.EventId} pedidoId={dados.PedidoId}");

        try
        {
            using var scope = scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<PagamentoDbContext>();

            // 1. Idempotência: já existe pagamento para esse pedido
            if (await db.Pagamentos.AnyAsync(p => p.PedidoId == dados.PedidoId))
            {
                Log.Warn($"pagamento duplicado ignorado pedidoId={dados.PedidoId} eventId={envelope.EventId}");
                canal.BasicAck(ea.DeliveryTag, multiple: false);
                return;
            }

            // 2. Simula o tempo de processamento (na demo dá para ver o pedido PENDENTE)
            await Task.Delay(cfg.DelayMs);

            // 3. Regra de aprovação
            var aprovado = dados.ValorTotalCentavos <= cfg.LimiteCentavos;
            var pagamento = new Pagamento
            {
                Id = Guid.NewGuid().ToString(),
                PedidoId = dados.PedidoId,
                ValorCentavos = dados.ValorTotalCentavos,
                Status = aprovado ? "APROVADO" : "RECUSADO",
                MotivoRecusa = aprovado ? null : "LIMITE_EXCEDIDO",
                EmailCliente = dados.EmailCliente,
                ProcessadoEm = Datas.Agora(),
            };

            // 4. Salva no MySQL
            db.Pagamentos.Add(pagamento);
            try
            {
                await db.SaveChangesAsync();
            }
            catch (DbUpdateException)
            {
                // Índice único em pedido_id: outra entrega do mesmo evento chegou primeiro
                Log.Warn($"pagamento duplicado ignorado pedidoId={dados.PedidoId} eventId={envelope.EventId}");
                canal.BasicAck(ea.DeliveryTag, multiple: false);
                return;
            }
            Log.Info($"pagamento processado id={pagamento.Id} pedidoId={pagamento.PedidoId} status={pagamento.Status}");

            // 5. Publica o resultado
            Publicar(pagamento);

            // 6. Confirma a mensagem só depois de salvar e publicar
            canal.BasicAck(ea.DeliveryTag, multiple: false);
        }
        catch (Exception e)
        {
            Log.Error($"erro ao processar evento eventId={envelope.EventId} detalhe=\"{e.Message}\"");
            canal.BasicNack(ea.DeliveryTag, multiple: false, requeue: false);
        }
    }

    private void Publicar(Pagamento p)
    {
        var routingKey = p.Status == "APROVADO" ? RoutingKeys.PagamentoAprovado : RoutingKeys.PagamentoRecusado;
        var eventId = Guid.NewGuid().ToString();

        var envelope = new Envelope<PagamentoResultadoDados>(
            EventId: eventId,
            Tipo: routingKey,
            Origem: cfg.Servico,
            OcorridoEm: Datas.Agora(),
            Dados: new PagamentoResultadoDados(
                PagamentoId: p.Id,
                PedidoId: p.PedidoId,
                ValorCentavos: p.ValorCentavos,
                Status: p.Status,
                MotivoRecusa: p.MotivoRecusa,
                EmailCliente: p.EmailCliente,
                ProcessadoEm: p.ProcessadoEm));

        var corpo = JsonSerializer.SerializeToUtf8Bytes(envelope, Json.Opcoes);

        // IModel não é thread-safe: um publish por vez
        lock (_lockPublicacao)
        {
            var canal = _canalPublicacao!;
            var props = canal.CreateBasicProperties();
            props.ContentType = "application/json";
            props.ContentEncoding = "utf-8";
            props.Persistent = true;          // delivery_mode = 2
            props.MessageId = eventId;
            props.Type = routingKey;

            canal.BasicPublish(
                exchange: cfg.Exchange, routingKey: routingKey, mandatory: false, basicProperties: props, body: corpo);
            canal.WaitForConfirmsOrDie(TimeSpan.FromSeconds(5));
        }

        Log.Info($"evento publicado tipo={routingKey} eventId={eventId} pedidoId={p.PedidoId}");
    }

    public override void Dispose()
    {
        try { _canalConsumo?.Close(); } catch { /* encerrando */ }
        try { _canalPublicacao?.Close(); } catch { /* encerrando */ }
        base.Dispose();
    }
}
