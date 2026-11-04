namespace MsPagamento.Domain;

/// <summary>Entidade persistida na tabela "pagamentos" (CONTRATOS.md, seção 5).</summary>
public class Pagamento
{
    public string Id { get; set; } = default!;
    public string PedidoId { get; set; } = default!;
    public int ValorCentavos { get; set; }
    public string Status { get; set; } = default!;          // APROVADO | RECUSADO
    public string? MotivoRecusa { get; set; }               // null | LIMITE_EXCEDIDO
    public string EmailCliente { get; set; } = default!;    // vai no evento, não aparece na API
    public string ProcessadoEm { get; set; } = default!;
}

/// <summary>JSON exposto pela API. Não inclui o e-mail do cliente.</summary>
public record PagamentoResposta(
    string Id,
    string PedidoId,
    int ValorCentavos,
    string Status,
    string? MotivoRecusa,
    string ProcessadoEm)
{
    public static PagamentoResposta De(Pagamento p) =>
        new(p.Id, p.PedidoId, p.ValorCentavos, p.Status, p.MotivoRecusa, p.ProcessadoEm);
}
