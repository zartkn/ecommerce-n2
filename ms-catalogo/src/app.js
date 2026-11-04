const express = require('express');
const crypto = require('crypto');
const config = require('./config');
const { Produto, paraJson } = require('./produto.model');
const { log, agora, erro } = require('./util');

const app = express();
app.disable('x-powered-by');
app.use(express.json());

// Toda resposta leva X-Pod-Name: é a evidência do balanceamento entre as 3 réplicas.
app.use((req, res, next) => {
  res.set('X-Pod-Name', config.podName);
  next();
});

// Usado pelas probes do Kubernetes. Não passa pelo Ingress.
app.get('/health', (req, res) => {
  res.json({ status: 'UP', servico: config.servico, pod: config.podName });
});

// GET /api/produtos: lista ordenada por id
app.get('/api/produtos', async (req, res, next) => {
  try {
    const docs = await Produto.find().sort({ _id: 1 }).lean();
    res.json(docs.map(paraJson));
  } catch (e) {
    next(e);
  }
});

// IMPORTANTE: declarada antes de /api/produtos/:id, senão "instance" vira um id.
app.get('/api/produtos/instance', (req, res) => {
  res.json({ servico: config.servico, pod: config.podName, timestamp: agora() });
});

// GET /api/produtos/:id: usado pelo Pedidos via Service Discovery
app.get('/api/produtos/:id', async (req, res, next) => {
  try {
    const doc = await Produto.findById(req.params.id).lean();
    if (!doc) {
      return erro(res, 404, 'PRODUTO_NAO_ENCONTRADO', `Produto ${req.params.id} não encontrado`);
    }
    log.info(`produto consultado id=${doc._id} pod=${config.podName}`);
    res.json(paraJson(doc));
  } catch (e) {
    next(e);
  }
});

// Validação do POST (CONTRATOS.md, seção 3). Devolve a mensagem de erro ou null.
function validarProduto(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'Corpo da requisição ausente ou inválido';
  if (typeof body.nome !== 'string' || body.nome.trim() === '') return 'nome é obrigatório e deve ser texto não vazio';
  if (!Number.isInteger(body.precoCentavos) || body.precoCentavos <= 0) return 'precoCentavos deve ser inteiro maior que zero';
  if (body.descricao !== undefined && body.descricao !== null && typeof body.descricao !== 'string') return 'descricao deve ser texto';
  if (body.disponivel !== undefined && body.disponivel !== null && typeof body.disponivel !== 'boolean') return 'disponivel deve ser booleano';
  return null;
}

// POST /api/produtos: cadastra produto com UUID v4
app.post('/api/produtos', async (req, res, next) => {
  const problema = validarProduto(req.body);
  if (problema) return erro(res, 400, 'DADOS_INVALIDOS', problema);

  try {
    const doc = await Produto.create({
      _id: crypto.randomUUID(),
      nome: req.body.nome.trim(),
      descricao: req.body.descricao ?? '',
      precoCentavos: req.body.precoCentavos,
      disponivel: req.body.disponivel ?? true,
      criadoEm: agora(),
    });
    log.info(`produto criado id=${doc._id} precoCentavos=${doc.precoCentavos}`);
    res.status(201).json(paraJson(doc.toObject()));
  } catch (e) {
    next(e);
  }
});

// Tratamento de erros: JSON malformado vira 400, o resto vira 500.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err && err.type === 'entity.parse.failed') {
    return erro(res, 400, 'DADOS_INVALIDOS', 'JSON inválido no corpo da requisição');
  }
  log.error(`erro nao tratado path=${req.path} detalhe="${err && err.message}"`);
  return erro(res, 500, 'ERRO_INTERNO', 'Erro interno no serviço de catálogo');
});

module.exports = app;
