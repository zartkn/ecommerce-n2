using MsPagamento.Infra;
using RabbitMQ.Client;

namespace MsPagamento.Messaging;

/// <summary>Conexão única com o RabbitMQ, compartilhada pelo consumidor e pela publicação.</summary>
public sealed class RabbitMqConexao(Config cfg) : IDisposable
{
    private IConnection? _conexao;

    public IConnection Conexao =>
        _conexao ?? throw new InvalidOperationException("RabbitMQ ainda não conectado");

    /// <summary>Conecta com retry: a cada 5 s, até 24 tentativas (seção 2.7).</summary>
    public void Conectar()
    {
        var factory = new ConnectionFactory
        {
            HostName = cfg.RabbitHost,
            Port = cfg.RabbitPort,
            UserName = cfg.RabbitUser,
            Password = cfg.RabbitPassword,
            VirtualHost = "/",
            AutomaticRecoveryEnabled = true,
            TopologyRecoveryEnabled = true,
            NetworkRecoveryInterval = TimeSpan.FromSeconds(5),
            DispatchConsumersAsync = true, // necessário para o AsyncEventingBasicConsumer
            ClientProvidedName = $"pagamento@{cfg.PodName}",
        };

        for (var tentativa = 1; tentativa <= Config.RetryTentativas; tentativa++)
        {
            try
            {
                _conexao = factory.CreateConnection();
                Log.Info($"rabbitmq conectado host={cfg.RabbitHost}");
                return;
            }
            catch (Exception e)
            {
                Log.Warn($"rabbitmq indisponivel tentativa={tentativa}/{Config.RetryTentativas} detalhe=\"{e.GetType().Name}\"");
                Thread.Sleep(Config.RetryIntervalo);
            }
        }

        throw new InvalidOperationException("nao foi possivel conectar no rabbitmq");
    }

    public void Dispose()
    {
        try { _conexao?.Close(); } catch { /* encerrando */ }
        _conexao?.Dispose();
    }
}
