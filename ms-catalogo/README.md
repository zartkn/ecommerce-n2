# ms-catalogo · Pedro

Node.js 20 + Express + MongoDB (Mongoose). Mantém a vitrine e é o serviço com **3 réplicas** no EKS.

| Arquivo | O que faz |
|---|---|
| `src/server.js` | conecta no Mongo com retry, roda o seed e sobe o HTTP |
| `src/app.js` | rotas, validação do POST, header `X-Pod-Name` e tratamento de erros |
| `src/produto.model.js` | schema Mongoose com `_id` string e conversão `_id` → `id` |
| `src/seed.js` | 6 produtos da seção 8 do contrato, com upsert seguro para 3 réplicas |
| `src/config.js` | variáveis de ambiente |

## Endpoints
- `GET /api/produtos` · `GET /api/produtos/{id}` · `POST /api/produtos`
- `GET /api/produtos/instance` → nome do Pod que respondeu (prova do balanceamento)
- `GET /health`

## Rodar sem Docker
```bash
npm install
MONGO_URL=mongodb://localhost:27017/catalogo npm start
```

## Para a apresentação
- Por que a rota `/instance` vem antes de `/:id` no Express
- Por que o seed usa upsert com `$setOnInsert` e ignora o erro 11000 (3 réplicas subindo juntas)
- `kubectl logs -l app=catalogo --prefix -f` mostrando as chamadas caindo em Pods diferentes
