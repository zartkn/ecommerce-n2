# ms-notificacao · Mickael

Python 3.12 + FastAPI + MongoDB (PyMongo async) + aio-pika. Avisa o cliente do resultado do pagamento.

| Arquivo | O que faz |
|---|---|
| `app/main.py` | rotas GET, header `X-Pod-Name` e tratamento de erros |
| `app/messaging.py` | consome `pagamento.*`, monta a mensagem e simula o e-mail no log |
| `app/db.py` | coleção `notificacoes` com índice único `pedidoId + tipo` |
| `app/util.py` | logs, datas e formatação de reais (69980 → `699,80`) |

## Endpoints
- `GET /api/notificacoes` (aceita `?pedidoId=`) · `GET /api/notificacoes/{id}`
- `GET /health` · Swagger em `/api/notificacoes/docs`

## Rodar sem Docker
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
MONGO_URL=mongodb://localhost:27017/notificacao RABBITMQ_HOST=localhost uvicorn app.main:app --port 8001
```

## Para a apresentação
- Por que existe uma fila só do Notificação (`notificacao.resultado-pagamento`) ligada a `pagamento.*`
- Idempotência pelo índice único: republicar a mesma mensagem pelo painel e mostrar `notificacao duplicada ignorada`
- `kubectl logs -f deploy/notificacao` com o `[EMAIL SIMULADO]`
