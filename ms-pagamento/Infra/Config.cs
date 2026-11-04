namespace MsPagamento.Infra;

/// <summary>
/// Configuração lida das variáveis de ambiente (CONTRATOS.md, seção 9).
/// Os valores padrão funcionam no docker-compose e no Kubernetes sem mudar nada.
/// </summary>
public sealed class Config
{
    public string Servico => "pagamento";
    public string PodName { get; } = Env("HOSTNAME", Environment.MachineName);

    public string DbHost { get; } = Env("DB_HOST", "mysql-pagamento");
    public int DbPort { get; } = int.Parse(Env("DB_PORT", "3306"));
    public string DbName { get; } = Env("DB_NAME", "pagamento");
    public string DbUser { get; } = Env("DB_USER", "pagamento");
    public string DbPassword { get; } = Env("DB_PASSWORD", "pagamento123");

    public string RabbitHost { get; } = Env("RABBITMQ_HOST", "rabbitmq");
    public int RabbitPort { get; } = int.Parse(Env("RABBITMQ_PORT", "5672"));
    public string RabbitUser { get; } = Env("RABBITMQ_USER", "ecommerce");
    public string RabbitPassword { get; } = Env("RABBITMQ_PASSWORD", "ecommerce123");
    public string Exchange { get; } = Env("RABBITMQ_EXCHANGE", "ecommerce.eventos");

    public int LimiteCentavos { get; } = int.Parse(Env("PAGAMENTO_LIMITE_CENTAVOS", "100000"));
    public int DelayMs { get; } = int.Parse(Env("PAGAMENTO_DELAY_MS", "2000"));

    // Topologia fixa do contrato (seção 7.4)
    public const string FilaConsumo = "pagamento.pedido-criado";
    public const string BindingConsumo = "pedido.criado";

    // Retry na subida (seção 2.7)
    public const int RetryTentativas = 24;
    public static readonly TimeSpan RetryIntervalo = TimeSpan.FromSeconds(5);

    // AllowPublicKeyRetrieval: o MySQL 8 usa caching_sha2_password e, sem TLS,
    // o driver precisa buscar a chave pública do servidor para autenticar.
    public string ConnectionString =>
        $"Server={DbHost};Port={DbPort};Database={DbName};User={DbUser};Password={DbPassword};" +
        "SslMode=Preferred;AllowPublicKeyRetrieval=True;";

    private static string Env(string chave, string padrao)
    {
        var valor = Environment.GetEnvironmentVariable(chave);
        return string.IsNullOrWhiteSpace(valor) ? padrao : valor;
    }
}
