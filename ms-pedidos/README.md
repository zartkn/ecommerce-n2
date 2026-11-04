# ms-pedidos · Edmund

Python 3.12 + FastAPI + MySQL (SQLAlchemy) + aio-pika. Orquestra o checkout.

| Arquivo | O que faz |
|---|---|
| `app/main.py` | rotas, validação (400 `DADOS_INVALIDOS`), sequência do POST |
| `app/catalogo_client.py` | chamada REST ao Catálogo por `http://catalogo:3000` (Service Discovery) |
| `app/messaging.py` | publica `pedido.criado` e consome `pagamento.*` |
| `app/db.py` | tabela `pedidos`, criação na subida e update idempotente |
| `app/config.py` | variáveis de ambiente e nomes de fila e routing key |

## Endpoints
- `POST /api/pedidos` · `GET /api/pedidos` · `GET /api/pedidos/{id}`
- `GET /health` · Swagger em `/api/pedidos/docs`

## Sequência do POST
1. valida o corpo
2. `GET http://catalogo:3000/api/produtos/{id}` (404, 422 ou 503 conforme a resposta)
3. calcula o total em centavos
4. grava `PENDENTE` com commit
5. publica `pedido.criado` com confirmação do broker; se falhar, apaga o pedido e devolve 503
6. em background, o consumidor recebe `pagamento.aprovado` ou `pagamento.recusado` e muda para `PAGO` ou `RECUSADO`

## Rodar sem Docker
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
DB_HOST=localhost CATALOGO_URL=http://localhost:3000 RABBITMQ_HOST=localhost uvicorn app.main:app --port 8000
```

## Para a apresentação
- REST síncrono + Service Discovery: `CATALOGO_URL` no YAML e o log `catalogo consultado ... pod=` variando entre as réplicas
- Por que o commit vem antes da publicação
- `kubectl logs -f deploy/pedidos` durante o fluxo
