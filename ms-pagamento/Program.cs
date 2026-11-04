// Microsserviço de Pagamento (C# .NET 8 + MySQL)
// Responsável: Marco. Consome pedido.criado, processa o pagamento (mock),
// salva no próprio MySQL e publica pagamento.aprovado ou pagamento.recusado.

using Microsoft.EntityFrameworkCore;
using MsPagamento.Data;
using MsPagamento.Domain;
using MsPagamento.Infra;
using MsPagamento.Messaging;

var cfg = new Config();
var builder = WebApplication.CreateBuilder(args);

// Deixa só os logs do contrato aparecendo no kubectl logs (o ASP.NET é bem verboso)
builder.Logging.SetMinimumLevel(LogLevel.Warning);

builder.Services.AddSingleton(cfg);
builder.Services.AddDbContext<PagamentoDbContext>(o =>
    // Versão fixa: o AutoDetect abriria conexão no registro e quebraria se o MySQL ainda não subiu
    o.UseMySql(cfg.ConnectionString, new MySqlServerVersion(new Version(8, 4, 0))));
builder.Services.AddSingleton<RabbitMqConexao>();
builder.Services.AddHostedService<PedidoCriadoConsumer>();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// ---------- Inicialização com retry (seção 2.7) ----------
if (!InicializarBanco(app.Services))
{
    Log.Error("nao foi possivel conectar no mysql, encerrando");
    Environment.Exit(1);
}

try
{
    app.Services.GetRequiredService<RabbitMqConexao>().Conectar();
}
catch (Exception e)
{
    Log.Error($"falha na inicializacao detalhe=\"{e.Message}\"");
    Environment.Exit(1);
}

// ---------- Middlewares ----------
app.UseExceptionHandler(erro => erro.Run(async ctx =>
{
    Log.Error($"erro nao tratado path={ctx.Request.Path}");
    ctx.Response.StatusCode = StatusCodes.Status500InternalServerError;
    ctx.Response.Headers["X-Pod-Name"] = cfg.PodName;
    await ctx.Response.WriteAsJsonAsync(
        new ErroResposta("ERRO_INTERNO", "Erro interno no serviço de pagamento", Datas.Agora()));
}));

app.Use(async (ctx, next) =>
{
    ctx.Response.Headers["X-Pod-Name"] = cfg.PodName;
    await next();
});

// Swagger dentro do base path para abrir pelo Ingress (seção 12)
app.UseSwagger(c => c.RouteTemplate = "api/pagamentos/swagger/{documentName}/swagger.json");
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/api/pagamentos/swagger/v1/swagger.json", "ms-pagamento v1");
    c.RoutePrefix = "api/pagamentos/swagger";
});

// ---------- Rotas ----------
app.MapGet("/health", () => Results.Ok(new { status = "UP", servico = cfg.Servico, pod = cfg.PodName }))
   .ExcludeFromDescription();

app.MapGet("/api/pagamentos", async (PagamentoDbContext db) =>
{
    var lista = await db.Pagamentos.AsNoTracking()
        .OrderByDescending(p => p.ProcessadoEm)
        .ToListAsync();
    return Results.Ok(lista.Select(PagamentoResposta.De));
});

app.MapGet("/api/pagamentos/{id}", async (string id, PagamentoDbContext db) =>
{
    var p = await db.Pagamentos.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id);
    return p is null
        ? ErroResposta.Http(404, "PAGAMENTO_NAO_ENCONTRADO", $"Pagamento {id} não encontrado")
        : Results.Ok(PagamentoResposta.De(p));
});

app.MapGet("/api/pagamentos/pedido/{pedidoId}", async (string pedidoId, PagamentoDbContext db) =>
{
    var p = await db.Pagamentos.AsNoTracking().FirstOrDefaultAsync(x => x.PedidoId == pedidoId);
    return p is null
        ? ErroResposta.Http(404, "PAGAMENTO_NAO_ENCONTRADO", $"Pagamento do pedido {pedidoId} não encontrado")
        : Results.Ok(PagamentoResposta.De(p));
});

Log.Info($"servico iniciado porta={Environment.GetEnvironmentVariable("ASPNETCORE_HTTP_PORTS") ?? "8080"} pod={cfg.PodName}");
app.Run();

// Conecta no MySQL e cria a tabela se não existir. Tenta a cada 5 s, até 24 vezes.
static bool InicializarBanco(IServiceProvider services)
{
    var cfg = services.GetRequiredService<Config>();
    for (var tentativa = 1; tentativa <= Config.RetryTentativas; tentativa++)
    {
        try
        {
            using var scope = services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<PagamentoDbContext>();
            db.Database.EnsureCreated();
            Log.Info($"mysql conectado host={cfg.DbHost} banco={cfg.DbName}");
            return true;
        }
        catch (Exception e)
        {
            Log.Warn($"mysql indisponivel tentativa={tentativa}/{Config.RetryTentativas} detalhe=\"{e.GetType().Name}\"");
            Thread.Sleep(Config.RetryIntervalo);
        }
    }
    return false;
}
