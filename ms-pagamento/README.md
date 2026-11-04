# ms-pagamento · Marco

C# .NET 8 (ASP.NET Core Minimal API) + MySQL (EF Core com Pomelo) + RabbitMQ.Client 6.8. Processa o pagamento (mock) a partir do evento `pedido.criado`.

| Arquivo | O que faz |
|---|---|
| `Program.cs` | DI, retry de MySQL e RabbitMQ na subida, middlewares, Swagger e rotas GET |
| `Messaging/PedidoCriadoConsumer.cs` | `BackgroundService` que consome, decide, grava e publica o resultado |
| `Messaging/RabbitMqConexao.cs` | conexão com retry e recuperação automática |
| `Messaging/Eventos.cs` | records do envelope e dos eventos (seção 7 do contrato) |
| `Data/PagamentoDbContext.cs` | mapeamento da tabela `pagamentos` em snake_case, `pedido_id` único |
| `Domain/Pagamento.cs` | entidade e DTO da API (sem o e-mail do cliente) |
| `Infra/` | configuração, logs, datas ISO 8601, JSON camelCase e corpo de erro |

## Endpoints
- `GET /api/pagamentos` · `GET /api/pagamentos/{id}` · `GET /api/pagamentos/pedido/{pedidoId}`
- `GET /health` · Swagger em `/api/pagamentos/swagger`
- Não existe POST: pagamento só nasce do evento

## Regra
`valorTotalCentavos <= PAGAMENTO_LIMITE_CENTAVOS` (padrão 100000) aprova; acima recusa com `LIMITE_EXCEDIDO`. Antes de decidir, espera `PAGAMENTO_DELAY_MS` (padrão 2000) para dar tempo de mostrar o pedido `PENDENTE` na demo.

## Rodar sem Docker
```bash
dotnet run      # com DB_HOST=localhost e RABBITMQ_HOST=localhost no ambiente
```

**Primeira coisa a fazer:** `dotnet build` e `docker build .` na sua máquina. O código foi compilado contra as assinaturas dos pacotes, mas o restore real do NuGet ainda não foi feito.

## Para a apresentação
- `BackgroundService` + `AsyncEventingBasicConsumer` com ack manual e `prefetch = 1`
- Idempotência: checagem por `pedido_id` + índice único no banco
- Canal de publicação separado, com `ConfirmSelect` e `WaitForConfirmsOrDie`
- `kubectl logs -f deploy/pagamento` durante o fluxo
