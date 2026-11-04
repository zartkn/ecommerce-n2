using System.Globalization;
using System.Text.Json;

namespace MsPagamento.Infra;

/// <summary>Logs no formato do contrato: [pagamento] NIVEL mensagem chave=valor</summary>
public static class Log
{
    public static void Info(string msg) => Console.WriteLine($"[pagamento] INFO {msg}");
    public static void Warn(string msg) => Console.WriteLine($"[pagamento] WARN {msg}");
    public static void Error(string msg) => Console.Error.WriteLine($"[pagamento] ERROR {msg}");
}

public static class Datas
{
    /// <summary>ISO 8601 em UTC com milissegundos e Z (seção 2.4).</summary>
    public static string Agora() =>
        DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
}

public static class Json
{
    /// <summary>camelCase na serialização manual das mensagens (o HTTP já usa por padrão).</summary>
    public static readonly JsonSerializerOptions Opcoes = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
    };
}

/// <summary>Corpo de erro padrão (seção 2.5).</summary>
public record ErroResposta(string Erro, string Mensagem, string Timestamp)
{
    public static IResult Http(int status, string codigo, string mensagem) =>
        Results.Json(new ErroResposta(codigo, mensagem, Datas.Agora()), statusCode: status);
}
