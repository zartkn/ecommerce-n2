namespace MsPagamento.Messaging;

/// <summary>Envelope igual para todos os eventos (CONTRATOS.md, seção 7.8).</summary>
public record Envelope<T>(string EventId, string Tipo, string Origem, string OcorridoEm, T Dados);

/// <summary>dados de pedido.criado (seção 7.9). Publicado pelo Pedidos.</summary>
public record PedidoCriadoDados(
    string PedidoId,
    string ProdutoId,
    string NomeProduto,
    int Quantidade,
    int ValorTotalCentavos,
    string EmailCliente);

/// <summary>dados de pagamento.aprovado e pagamento.recusado (seção 7.9).</summary>
public record PagamentoResultadoDados(
    string PagamentoId,
    string PedidoId,
    int ValorCentavos,
    string Status,
    string? MotivoRecusa,
    string EmailCliente,
    string ProcessadoEm);

public static class RoutingKeys
{
    public const string PedidoCriado = "pedido.criado";
    public const string PagamentoAprovado = "pagamento.aprovado";
    public const string PagamentoRecusado = "pagamento.recusado";
}
