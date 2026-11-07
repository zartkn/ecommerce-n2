# Contratos do projeto · E-commerce N2 (Back-End: Cloud Computing)

Versão 1.2 · 04/11/2026

Este arquivo é a fonte única da verdade da integração. Tudo aqui é obrigatório, a não ser o que estiver marcado como **(recomendado)**. Mudou alguma coisa? Avisa no grupo e atualiza este arquivo no mesmo commit, subindo a versão.

---

## 1. Visão geral

| Serviço | Responsável | Linguagem | Banco | Réplicas | Porta |
|---|---|---|---|---|---|
| `catalogo` | Pedro | Node.js 20 (Express) | MongoDB 7 (`mongo-catalogo`) | **3** | 3000 |
| `pedidos` | Edmund | Python 3.12 (FastAPI) | MySQL 8.4 (`mysql-pedidos`) | 1 | 8000 |
| `pagamento` | Marco | C# .NET 8 (ASP.NET Core) | MySQL 8.4 (`mysql-pagamento`) | 1 | 8080 |
| `notificacao` | Mickael | Python 3.12 (FastAPI) | MongoDB 7 (`mongo-notificacao`) | 1 | 8001 |

Infra compartilhada: `rabbitmq` (RabbitMQ 3.13 com painel de gerenciamento) e NGINX Ingress Controller.

### Fluxo principal

```
1. Cliente  → POST /api/pedidos                         (via Ingress)
2. pedidos  → GET http://catalogo:3000/api/produtos/{id} (REST + Service Discovery)
3. pedidos  → salva PENDENTE no MySQL → publica pedido.criado
4. pagamento ← consome pedido.criado → decide → salva no MySQL → publica pagamento.aprovado | pagamento.recusado
5. pedidos   ← consome pagamento.*  → atualiza status para PAGO | RECUSADO
6. notificacao ← consome pagamento.* → grava notificação no Mongo → log "[EMAIL SIMULADO]"
```

---

## 2. Convenções gerais

### 2.1 JSON
- Campos sempre em **camelCase**, inclusive no Python e no C#.
- `Content-Type: application/json; charset=utf-8`.
- Campo sem valor vai como `null`. Nunca omitir campo do contrato.

### 2.2 IDs
- Todos os IDs são **string** no JSON e `VARCHAR(36)` no MySQL.
- Produtos do seed usam IDs fixos (`prod-001`...). Produto criado por `POST` recebe UUID v4.
- Pedidos, pagamentos, notificações e eventos usam **UUID v4** gerado pelo próprio serviço.
- No Mongo, o ID vai no próprio `_id` como string (não usar ObjectId) e é exposto como `id` no JSON.

### 2.3 Dinheiro
- Sempre **inteiro em centavos**. Campos terminam em `Centavos`.
- Exemplo: R$ 349,90 = `34990`.
- Proibido float/double/decimal no JSON.

### 2.4 Datas
- ISO 8601 em UTC com milissegundos e `Z`: `2026-11-08T14:30:00.000Z`.
- Como gerar:
  - Node: `new Date().toISOString()`
  - Python: `datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")`
  - C#: `DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")`
- Ninguém faz conta com data de outro serviço. Data recebida é só guardada e exibida.

### 2.5 Formato de erro (todas as APIs)

```json
{
  "erro": "PRODUTO_NAO_ENCONTRADO",
  "mensagem": "Produto prod-999 não encontrado",
  "timestamp": "2026-11-08T14:30:00.000Z"
}
```

| Código `erro` | HTTP | Quando |
|---|---|---|
| `DADOS_INVALIDOS` | 400 | Corpo ausente, campo faltando, tipo errado ou valor fora da regra |
| `PRODUTO_NAO_ENCONTRADO` | 404 | Produto não existe |
| `PEDIDO_NAO_ENCONTRADO` | 404 | Pedido não existe |
| `PAGAMENTO_NAO_ENCONTRADO` | 404 | Pagamento não existe |
| `NOTIFICACAO_NAO_ENCONTRADA` | 404 | Notificação não existe |
| `PRODUTO_INDISPONIVEL` | 422 | Produto existe mas `disponivel = false` |
| `CATALOGO_INDISPONIVEL` | 503 | Pedidos não conseguiu falar com o Catálogo (erro de conexão, timeout ou 5xx) |
| `MENSAGERIA_INDISPONIVEL` | 503 | Falha ao publicar no RabbitMQ |
| `ERRO_INTERNO` | 500 | Qualquer outra exceção não tratada |

Observação para o FastAPI: o erro de validação padrão (422 com `detail`) tem que ser convertido para 400 `DADOS_INVALIDOS` com um `exception_handler` de `RequestValidationError`.

### 2.6 Endpoints comuns (todos os serviços)
- `GET /health` → `200 {"status": "UP", "servico": "<nome>", "pod": "<HOSTNAME>"}`. Usado pelas probes do Kubernetes. Não passa pelo Ingress.
- Toda resposta HTTP leva o header `X-Pod-Name: <HOSTNAME>`. Obrigatório no `catalogo`, **(recomendado)** nos demais.

### 2.7 Inicialização e retry
- Na subida, cada serviço tenta conectar no banco e no RabbitMQ **a cada 5 segundos, até 24 tentativas** (2 minutos). Se não conseguir, encerra com código 1 e o Kubernetes reinicia o Pod.
- Tabelas e índices são criados pelo próprio serviço na subida (sem migrations):
  - Python: `Base.metadata.create_all(engine)`
  - C#: `db.Database.EnsureCreated()`
  - Mongo: `createIndex` na subida (idempotente)

### 2.8 Logs
Formato: `[servico] NIVEL mensagem chave=valor`. As linhas obrigatórias de cada serviço estão na seção dele. Elas são a evidência da demo com `kubectl logs -f`.

---

## 3. Catálogo · Pedro

Base path: `/api/produtos`

### Modelo `Produto`

```json
{
  "id": "prod-001",
  "nome": "Teclado Mecânico ABNT2",
  "descricao": "Switch marrom, retroiluminado",
  "precoCentavos": 34990,
  "disponivel": true,
  "criadoEm": "2026-11-08T14:30:00.000Z"
}
```

Coleção Mongo: `produtos` no banco `catalogo`. Documento: `_id` (string), `nome`, `descricao`, `precoCentavos`, `disponivel`, `criadoEm`.

### Endpoints

| Método | Path | Sucesso | Erros |
|---|---|---|---|
| GET | `/api/produtos` | 200 `Produto[]` ordenado por `id` | 500 |
| GET | `/api/produtos/instance` | 200 `{"servico": "catalogo", "pod": "<HOSTNAME>", "timestamp": "..."}` | |
| GET | `/api/produtos/{id}` | 200 `Produto` | 404 `PRODUTO_NAO_ENCONTRADO` |
| POST | `/api/produtos` | 201 `Produto` | 400 `DADOS_INVALIDOS` |

**Atenção:** no Express, a rota `/api/produtos/instance` tem que ser declarada **antes** de `/api/produtos/:id`. Senão o Express trata "instance" como ID e devolve 404.

**POST** corpo:
```json
{ "nome": "Mousepad XL", "descricao": "90x40cm", "precoCentavos": 7990, "disponivel": true }
```
Regras: `nome` string não vazia, `precoCentavos` inteiro > 0, `descricao` string (pode ser vazia), `disponivel` boolean (padrão `true` se omitido). ID gerado como UUID v4.

### Seed
- Ativado por `SEED_ON_START=true`.
- Fazer **upsert por `_id`** (`updateOne({_id}, {$setOnInsert: {...}}, {upsert: true})`), e não "inserir se a coleção estiver vazia". Como são 3 réplicas subindo juntas, o "se estiver vazia" pode duplicar ou dar erro de chave.
- Dados na seção 8.

### Logs obrigatórios
```
[catalogo] INFO produto consultado id=prod-001 pod=catalogo-7f9c-abcde
[catalogo] INFO seed concluido produtos=6
```

### Libs **(recomendado)**
`express`, `mongoose`, `uuid` (ou `crypto.randomUUID()`).

---

## 4. Pedidos · Edmund

Base path: `/api/pedidos`

### Modelo `Pedido`

```json
{
  "id": "b3f1c2a4-...",
  "produtoId": "prod-001",
  "nomeProduto": "Teclado Mecânico ABNT2",
  "precoUnitarioCentavos": 34990,
  "quantidade": 2,
  "valorTotalCentavos": 69980,
  "emailCliente": "cliente@email.com",
  "status": "PENDENTE",
  "motivoRecusa": null,
  "criadoEm": "2026-11-08T14:30:00.000Z",
  "atualizadoEm": "2026-11-08T14:30:00.000Z"
}
```

`status`: `PENDENTE` | `PAGO` | `RECUSADO`.
`nomeProduto` e `precoUnitarioCentavos` são uma cópia do Catálogo no momento da compra. O Pedidos não consulta o Catálogo de novo depois disso (Database per Service).

### Tabela MySQL `pedidos` (banco `pedidos`)

| Coluna | Tipo |
|---|---|
| `id` | VARCHAR(36) PK |
| `produto_id` | VARCHAR(36) NOT NULL |
| `nome_produto` | VARCHAR(200) NOT NULL |
| `preco_unitario_centavos` | INT NOT NULL |
| `quantidade` | INT NOT NULL |
| `valor_total_centavos` | INT NOT NULL |
| `email_cliente` | VARCHAR(200) NOT NULL |
| `status` | VARCHAR(20) NOT NULL |
| `motivo_recusa` | VARCHAR(50) NULL |
| `criado_em` | VARCHAR(30) NOT NULL |
| `atualizado_em` | VARCHAR(30) NOT NULL |

(Colunas em snake_case no banco, camelCase no JSON.)

### Endpoints

| Método | Path | Sucesso | Erros |
|---|---|---|---|
| POST | `/api/pedidos` | 201 `Pedido` com status `PENDENTE` | 400, 404 `PRODUTO_NAO_ENCONTRADO`, 422 `PRODUTO_INDISPONIVEL`, 503 `CATALOGO_INDISPONIVEL`, 503 `MENSAGERIA_INDISPONIVEL` |
| GET | `/api/pedidos` | 200 `Pedido[]` do mais novo para o mais antigo | |
| GET | `/api/pedidos/{id}` | 200 `Pedido` | 404 `PEDIDO_NAO_ENCONTRADO` |

**POST** corpo:
```json
{ "produtoId": "prod-001", "quantidade": 2, "emailCliente": "cliente@email.com" }
```
Regras: `produtoId` string não vazia, `quantidade` inteiro de 1 a 10, `emailCliente` contendo `@`.

**Sequência do POST** (nesta ordem):
1. Valida o corpo → 400 se inválido.
2. `GET {CATALOGO_URL}/api/produtos/{produtoId}` com timeout de `CATALOGO_TIMEOUT_MS`.
   - 404 do Catálogo → devolve 404 `PRODUTO_NAO_ENCONTRADO`
   - erro de conexão, timeout ou 5xx → devolve 503 `CATALOGO_INDISPONIVEL`
   - `disponivel = false` → devolve 422 `PRODUTO_INDISPONIVEL`
3. Calcula `valorTotalCentavos = precoCentavos * quantidade`.
4. Insere com `PENDENTE` e **faz commit**.
5. Publica `pedido.criado` (seção 7).
6. Publicou → 201. Falhou → apaga o pedido recém-criado → 503 `MENSAGERIA_INDISPONIVEL`.

(O commit vem antes da publicação de propósito. Se fosse o contrário, o Pagamento poderia responder antes do commit, o consumidor do Pedidos não acharia o pedido e ele ficaria `PENDENTE` para sempre.)

A publicação usa **confirmação do broker** e `mandatory = true`. Se o exchange não tiver nenhuma fila ligada a `pedido.criado` (o Pagamento nunca subiu e a fila dele ainda não existe), o RabbitMQ devolve a mensagem e isso também conta como falha: 503 `MENSAGERIA_INDISPONIVEL`. Sem isso a mensagem sumiria em silêncio e o pedido ficaria `PENDENTE` para sempre.

### Consumidor
Fila `pedidos.resultado-pagamento` (seção 7).
- `pagamento.aprovado` → `status = PAGO`, `atualizadoEm = agora`.
- `pagamento.recusado` → `status = RECUSADO`, `motivoRecusa = dados.motivoRecusa`, `atualizadoEm = agora`.
- Pedido já não está `PENDENTE` → ignora e dá ack (idempotência).
- Pedido não existe → log WARN e ack.

### Logs obrigatórios
```
[pedidos] INFO catalogo consultado produtoId=prod-001 pod=catalogo-7f9c-abcde
[pedidos] INFO pedido criado id=... valorTotalCentavos=69980
[pedidos] INFO evento publicado tipo=pedido.criado eventId=... pedidoId=...
[pedidos] INFO evento recebido tipo=pagamento.aprovado eventId=... pedidoId=...
[pedidos] INFO pedido atualizado id=... status=PAGO
[pedidos] WARN evento duplicado ignorado pedidoId=... eventId=...
```
(O `pod` no primeiro log vem do header `X-Pod-Name` da resposta do Catálogo.)

### Libs **(recomendado)**
`fastapi`, `uvicorn`, `sqlalchemy`, `pymysql`, `httpx`, `aio-pika` (usar `connect_robust`, iniciado no `lifespan` do FastAPI).

---

## 5. Pagamento · Marco

Base path: `/api/pagamentos`. Não recebe criação por HTTP: pagamento só nasce a partir do evento `pedido.criado`.

### Modelo `Pagamento`

```json
{
  "id": "9a7e...",
  "pedidoId": "b3f1c2a4-...",
  "valorCentavos": 69980,
  "status": "APROVADO",
  "motivoRecusa": null,
  "processadoEm": "2026-11-08T14:30:02.000Z"
}
```

`status`: `APROVADO` | `RECUSADO`. `motivoRecusa`: `null` ou `LIMITE_EXCEDIDO`.

### Tabela MySQL `pagamentos` (banco `pagamento`)

| Coluna | Tipo |
|---|---|
| `id` | VARCHAR(36) PK |
| `pedido_id` | VARCHAR(36) NOT NULL **UNIQUE** |
| `valor_centavos` | INT NOT NULL |
| `status` | VARCHAR(20) NOT NULL |
| `motivo_recusa` | VARCHAR(50) NULL |
| `email_cliente` | VARCHAR(200) NOT NULL |
| `processado_em` | VARCHAR(30) NOT NULL |

(`email_cliente` é guardado porque vai no evento de saída, mas não aparece no JSON da API.)

### Endpoints

| Método | Path | Sucesso | Erros |
|---|---|---|---|
| GET | `/api/pagamentos` | 200 `Pagamento[]` do mais novo para o mais antigo | |
| GET | `/api/pagamentos/{id}` | 200 `Pagamento` | 404 `PAGAMENTO_NAO_ENCONTRADO` |
| GET | `/api/pagamentos/pedido/{pedidoId}` | 200 `Pagamento` | 404 `PAGAMENTO_NAO_ENCONTRADO` |

### Consumidor
Fila `pagamento.pedido-criado` (seção 7). Para cada mensagem:
1. Já existe pagamento com esse `pedidoId` → log WARN, ack, fim (idempotência).
2. Espera `PAGAMENTO_DELAY_MS` (simula o processamento, e na demo dá tempo de mostrar o pedido `PENDENTE` antes de virar `PAGO`).
3. Regra: `valorTotalCentavos <= PAGAMENTO_LIMITE_CENTAVOS` → `APROVADO`. Senão → `RECUSADO` com `motivoRecusa = "LIMITE_EXCEDIDO"`.
4. Salva no MySQL.
5. Publica `pagamento.aprovado` ou `pagamento.recusado`.
6. Ack.

### Logs obrigatórios
```
[pagamento] INFO evento recebido tipo=pedido.criado eventId=... pedidoId=...
[pagamento] INFO pagamento processado id=... pedidoId=... status=APROVADO
[pagamento] INFO evento publicado tipo=pagamento.aprovado eventId=... pedidoId=...
[pagamento] WARN pagamento duplicado ignorado pedidoId=... eventId=...
```

### Libs **(recomendado)**
- ASP.NET Core 8 Minimal API
- `Pomelo.EntityFrameworkCore.MySql` 8.x
- `RabbitMQ.Client` **6.8.x** (a 7.x mudou a API inteira para assíncrona e a maioria dos tutoriais ainda é da 6.x). Ligar `AutomaticRecoveryEnabled = true`.
- Consumidor rodando num `BackgroundService` registrado com `AddHostedService`.
- `JsonSerializerOptions` com `PropertyNamingPolicy = JsonNamingPolicy.CamelCase` (o ASP.NET já faz isso nas respostas HTTP, mas a serialização manual das mensagens precisa configurar).

---

## 6. Notificação · Mickael

Base path: `/api/notificacoes`

### Modelo `Notificacao`

```json
{
  "id": "5d2c...",
  "pedidoId": "b3f1c2a4-...",
  "emailCliente": "cliente@email.com",
  "tipo": "PAGAMENTO_APROVADO",
  "canal": "EMAIL_SIMULADO",
  "mensagem": "Seu pagamento de R$ 699,80 foi aprovado. Seu pedido já está sendo separado.",
  "eventId": "e81f...",
  "criadoEm": "2026-11-08T14:30:02.500Z"
}
```

`tipo`: `PAGAMENTO_APROVADO` | `PAGAMENTO_RECUSADO`. `canal` é sempre `EMAIL_SIMULADO`.

Coleção Mongo `notificacoes` no banco `notificacao`, com **índice único** em `{pedidoId: 1, tipo: 1}`.

### Textos da mensagem
- Aprovado: `Seu pagamento de R$ {valor} foi aprovado. Seu pedido já está sendo separado.`
- Recusado: `Seu pagamento de R$ {valor} foi recusado (limite excedido). Tente novamente com outro valor.`

`{valor}` formatado em reais a partir dos centavos (69980 → `699,80`).

### Endpoints

| Método | Path | Sucesso | Erros |
|---|---|---|---|
| GET | `/api/notificacoes` | 200 `Notificacao[]` do mais novo para o mais antigo. Aceita filtro `?pedidoId=...` | |
| GET | `/api/notificacoes/{id}` | 200 `Notificacao` | 404 `NOTIFICACAO_NAO_ENCONTRADA` |

### Consumidor
Fila `notificacao.resultado-pagamento` (seção 7). Para cada mensagem:
1. Monta a notificação conforme `tipo` do evento.
2. Insere no Mongo.
   - Erro de chave duplicada (código 11000) → log `notificacao duplicada ignorada` e ack.
3. Log `[EMAIL SIMULADO]`.
4. Ack.

### Logs obrigatórios
```
[notificacao] INFO evento recebido tipo=pagamento.aprovado eventId=... pedidoId=...
[notificacao] INFO [EMAIL SIMULADO] para=cliente@email.com mensagem="Seu pagamento de R$ 699,80 foi aprovado..."
[notificacao] WARN notificacao duplicada ignorada pedidoId=... tipo=PAGAMENTO_APROVADO
```

### Libs **(recomendado)**
`fastapi`, `uvicorn`, `pymongo` (com `AsyncMongoClient`) ou `motor`, `aio-pika` com `connect_robust`.

---

## 7. RabbitMQ

### 7.1 Broker
- Imagem: `rabbitmq:3.13-management`
- Usuário e senha: `ecommerce` / `ecommerce123` (definidos por `RABBITMQ_DEFAULT_USER` e `RABBITMQ_DEFAULT_PASS`). O usuário padrão `guest` só funciona em localhost e **não** serve entre containers.
- Vhost: `/`
- Portas: 5672 (AMQP) e 15672 (painel)

### 7.2 Exchange

| Nome | Tipo | durable | autoDelete |
|---|---|---|---|
| `ecommerce.eventos` | `topic` | `true` | `false` |

### 7.3 Routing keys
- `pedido.criado`
- `pagamento.aprovado`
- `pagamento.recusado`

### 7.4 Filas

| Fila | Binding | Consumidor | durable | exclusive | autoDelete |
|---|---|---|---|---|---|
| `pagamento.pedido-criado` | `pedido.criado` | pagamento | true | false | false |
| `pedidos.resultado-pagamento` | `pagamento.*` | pedidos | true | false | false |
| `notificacao.resultado-pagamento` | `pagamento.*` | notificacao | true | false | false |

Nenhuma fila tem argumentos extras (sem TTL, sem DLQ).

### 7.5 Quem declara o quê
- **Quem publica** declara o exchange antes de publicar.
- **Quem consome** declara o exchange, a própria fila e o binding na subida.
- Todo mundo usa **exatamente** os parâmetros das tabelas acima. Qualquer diferença (por exemplo `durable=false` em um serviço e `true` em outro) faz o RabbitMQ recusar com `PRECONDITION_FAILED` e derruba a conexão.

### 7.6 Publicação
- `content_type = application/json`, corpo em UTF-8
- `delivery_mode = 2` (persistente)
- `message_id = eventId`
- `type = <routing key>`

### 7.7 Consumo
- **Ack manual**, sempre depois de salvar no banco.
- `prefetch = 1`.
- JSON inválido ou campo obrigatório faltando → log ERROR e `nack` com `requeue=false` (mensagem descartada).
- Exceção no processamento → log ERROR com o `eventId` e `nack` com `requeue=false`. Sem retry automático, para não criar loop infinito na demo.
- Mensagem duplicada detectada → log WARN e **ack** (não é erro).

### 7.8 Envelope (igual para todos os eventos)

```json
{
  "eventId": "uuid-v4",
  "tipo": "pedido.criado",
  "origem": "pedidos",
  "ocorridoEm": "2026-11-08T14:30:00.000Z",
  "dados": { }
}
```

`tipo` é igual à routing key. `origem` é o nome do serviço que publicou.

### 7.9 `dados` de cada evento

**`pedido.criado`** (origem `pedidos`)
```json
{
  "pedidoId": "b3f1c2a4-...",
  "produtoId": "prod-001",
  "nomeProduto": "Teclado Mecânico ABNT2",
  "quantidade": 2,
  "valorTotalCentavos": 69980,
  "emailCliente": "cliente@email.com"
}
```

**`pagamento.aprovado`** e **`pagamento.recusado`** (origem `pagamento`)
```json
{
  "pagamentoId": "9a7e...",
  "pedidoId": "b3f1c2a4-...",
  "valorCentavos": 69980,
  "status": "APROVADO",
  "motivoRecusa": null,
  "emailCliente": "cliente@email.com",
  "processadoEm": "2026-11-08T14:30:02.000Z"
}
```
No recusado: `"status": "RECUSADO"` e `"motivoRecusa": "LIMITE_EXCEDIDO"`.

---

## 8. Seed do Catálogo

| id | nome | descricao | precoCentavos | disponivel | Uso na demo |
|---|---|---|---|---|---|
| `prod-001` | Teclado Mecânico ABNT2 | Switch marrom, retroiluminado | 34990 | true | Caminho feliz |
| `prod-002` | Mouse Gamer sem Fio | 16000 DPI, bateria recarregável | 18990 | true | Recusa por quantidade |
| `prod-003` | Headset USB 7.1 | Microfone removível | 24990 | true | Pedido extra |
| `prod-004` | Monitor 27" QHD 165Hz | Painel IPS, 1ms | 189990 | true | Recusa por valor |
| `prod-005` | Webcam Full HD | 1080p, microfone embutido | 29990 | **false** | Produto indisponível |
| `prod-006` | Cabo HDMI 2.1 2m | Suporta 4K 120Hz | 3990 | true | Pedido barato |

`criadoEm` do seed: `2026-11-01T00:00:00.000Z`.

### Cenários de teste prontos

| # | Corpo do POST /api/pedidos | Resultado esperado |
|---|---|---|
| 1 | `prod-001`, qtd 2 | 201 → total 69980 → **PAGO** |
| 2 | `prod-004`, qtd 1 | 201 → total 189990 → **RECUSADO** |
| 3 | `prod-002`, qtd 6 | 201 → total 113940 → **RECUSADO** |
| 4 | `prod-005`, qtd 1 | **422** `PRODUTO_INDISPONIVEL` |
| 5 | `prod-999`, qtd 1 | **404** `PRODUTO_NAO_ENCONTRADO` |
| 6 | `prod-001`, qtd 0 | **400** `DADOS_INVALIDOS` |
| 7 | Republicar pelo painel do RabbitMQ o mesmo `pagamento.aprovado` do cenário 1 | Pedido continua PAGO e o Notificação loga `duplicada ignorada` |

---

## 9. Variáveis de ambiente

Os nomes dos hosts são **iguais** no `docker-compose` e no Kubernetes (o nome do serviço no compose é o mesmo nome do Service no K8s). Assim os valores padrão abaixo funcionam nos dois ambientes sem mudar nada.

### catalogo
| Variável | Padrão |
|---|---|
| `PORT` | `3000` |
| `MONGO_URL` | `mongodb://mongo-catalogo:27017/catalogo` |
| `SEED_ON_START` | `true` |

### pedidos
| Variável | Padrão |
|---|---|
| `PORT` | `8000` |
| `DB_HOST` | `mysql-pedidos` |
| `DB_PORT` | `3306` |
| `DB_NAME` | `pedidos` |
| `DB_USER` | `pedidos` |
| `DB_PASSWORD` | `pedidos123` |
| `CATALOGO_URL` | `http://catalogo:3000` |
| `CATALOGO_TIMEOUT_MS` | `3000` |
| `RABBITMQ_HOST` | `rabbitmq` |
| `RABBITMQ_PORT` | `5672` |
| `RABBITMQ_USER` | `ecommerce` |
| `RABBITMQ_PASSWORD` | `ecommerce123` |
| `RABBITMQ_EXCHANGE` | `ecommerce.eventos` |

### pagamento
| Variável | Padrão |
|---|---|
| `ASPNETCORE_HTTP_PORTS` | `8080` |
| `DB_HOST` | `mysql-pagamento` |
| `DB_PORT` | `3306` |
| `DB_NAME` | `pagamento` |
| `DB_USER` | `pagamento` |
| `DB_PASSWORD` | `pagamento123` |
| `RABBITMQ_HOST` | `rabbitmq` |
| `RABBITMQ_PORT` | `5672` |
| `RABBITMQ_USER` | `ecommerce` |
| `RABBITMQ_PASSWORD` | `ecommerce123` |
| `RABBITMQ_EXCHANGE` | `ecommerce.eventos` |
| `PAGAMENTO_LIMITE_CENTAVOS` | `100000` |
| `PAGAMENTO_DELAY_MS` | `2000` |

### notificacao
| Variável | Padrão |
|---|---|
| `PORT` | `8001` |
| `MONGO_URL` | `mongodb://mongo-notificacao:27017/notificacao` |
| `RABBITMQ_HOST` | `rabbitmq` |
| `RABBITMQ_PORT` | `5672` |
| `RABBITMQ_USER` | `ecommerce` |
| `RABBITMQ_PASSWORD` | `ecommerce123` |
| `RABBITMQ_EXCHANGE` | `ecommerce.eventos` |

### Bancos e broker
| Container | Variáveis |
|---|---|
| `mysql-pedidos` | `MYSQL_DATABASE=pedidos`, `MYSQL_USER=pedidos`, `MYSQL_PASSWORD=pedidos123`, `MYSQL_ROOT_PASSWORD=root123` |
| `mysql-pagamento` | `MYSQL_DATABASE=pagamento`, `MYSQL_USER=pagamento`, `MYSQL_PASSWORD=pagamento123`, `MYSQL_ROOT_PASSWORD=root123` |
| `mongo-catalogo` | nenhuma (sem autenticação, acessível só dentro do cluster) |
| `mongo-notificacao` | nenhuma (sem autenticação, acessível só dentro do cluster) |
| `rabbitmq` | `RABBITMQ_DEFAULT_USER=ecommerce`, `RABBITMQ_DEFAULT_PASS=ecommerce123` |

No Kubernetes as senhas ficam num Secret chamado `ecommerce-secrets` e entram nos Deployments por `secretKeyRef`. Os demais valores vão direto no `env` do Deployment.

---

## 10. Kubernetes

### 10.1 Recursos

| Deployment / Service | Imagem | Réplicas | containerPort = port = targetPort |
|---|---|---|---|
| `catalogo` | `usuario-pedro/ms-catalogo:1.0.0` | 3 | 3000 |
| `pedidos` | `usuario-edmund/ms-pedidos:1.0.0` | 1 | 8000 |
| `pagamento` | `usuario-marco/ms-pagamento:1.0.0` | 1 | 8080 |
| `notificacao` | `usuario-mickael/ms-notificacao:1.0.0` | 1 | 8001 |

(`usuario-...` é placeholder. O `scripts/build-push.sh` troca pelo usuário real do Docker Hub de cada um.)
| `mongo-catalogo` | `mongo:7` | 1 | 27017 |
| `mongo-notificacao` | `mongo:7` | 1 | 27017 |
| `mysql-pedidos` | `mysql:8.4` | 1 | 3306 |
| `mysql-pagamento` | `mysql:8.4` | 1 | 3306 |
| `rabbitmq` | `rabbitmq:3.13-management` | 1 | 5672 e 15672 |

- Namespace: `default`.
- Todos os Services são `ClusterIP`. Só o NGINX Ingress Controller fica exposto.
- Label padrão: `app: <nome>`. O `selector` do Service e os `labels` do template do Pod usam exatamente esse valor.
- Port, targetPort e containerPort são **iguais** de propósito: a URL interna fica igual no compose e no cluster (`http://catalogo:3000`).
- Bancos sem volume persistente (dados somem se o Pod reiniciar). Escolha consciente por causa das limitações de IAM do Learner Lab.
- Imagem com tag versionada (nunca `latest`). Mudou o código, sobe a tag (`1.0.1`) e atualiza o YAML.

### 10.2 Probes (serviços da aplicação)
```yaml
readinessProbe:
  httpGet: { path: /health, port: <porta> }
  initialDelaySeconds: 10    # catalogo: 3
  periodSeconds: 5           # catalogo: 2
livenessProbe:
  httpGet: { path: /health, port: <porta> }
  initialDelaySeconds: 150   # margem para o retry de 2 minutos da subida
  periodSeconds: 10
```

O `catalogo` tem readiness mais rápida de propósito: no `kubectl scale` ao vivo da apresentação, as réplicas novas ficam prontas em uns 5 segundos.

### 10.3 Ingress

| Path | pathType | Service | Porta |
|---|---|---|---|
| `/api/produtos` | Prefix | `catalogo` | 3000 |
| `/api/pedidos` | Prefix | `pedidos` | 8000 |
| `/api/pagamentos` | Prefix | `pagamento` | 8080 |
| `/api/notificacoes` | Prefix | `notificacao` | 8001 |

- Controller: NGINX Ingress Controller `controller-v1.15.1`, manifesto oficial do provider AWS (cria um Network Load Balancer).
- Nome: `ecommerce-ingress`, `ingressClassName: nginx`, sem `host` e sem rewrite.
- Acesso pelo hostname do Load Balancer: `kubectl get svc -n ingress-nginx ingress-nginx-controller`.

---

## 11. Docker

| Serviço | Imagem base **(recomendado)** |
|---|---|
| catalogo | `node:20-alpine` |
| pedidos | `python:3.12-slim` |
| notificacao | `python:3.12-slim` |
| pagamento | build com `mcr.microsoft.com/dotnet/sdk:8.0`, runtime com `mcr.microsoft.com/dotnet/aspnet:8.0` (multi-stage) |

Cada integrante publica a própria imagem na própria conta do Docker Hub, como pública, sempre em **linux/amd64** (arquitetura dos nós do EKS). Quem builda num Mac com chip Apple sem `--platform linux/amd64` gera imagem arm64 e o Pod quebra com `exec format error`. O `scripts/build-push.sh` já faz isso.

---

## 12. Swagger **(recomendado)**

Para a documentação abrir pelo Ingress, ela tem que ficar dentro do base path de cada serviço:
- FastAPI: `FastAPI(docs_url="/api/pedidos/docs", openapi_url="/api/pedidos/openapi.json")` (mesmo esquema no Notificação com `/api/notificacoes`)
- C#: Swashbuckle com `RoutePrefix = "api/pagamentos/swagger"` e o JSON em `/api/pagamentos/swagger/v1/swagger.json`
- Node: opcional

---

## Histórico
- 1.0 (03/11/2026): primeira versão
- 1.1 (03/11/2026): Pedidos faz commit antes de publicar e usa `mandatory` na publicação; logs de duplicidade; placeholders de imagem; versão do Ingress Controller; build em linux/amd64
- 1.2 (04/11/2026): probes da seção 10.2 alinhadas com os YAML (liveness 150 s) e readiness rápida no catalogo
