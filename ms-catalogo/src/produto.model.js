const mongoose = require('mongoose');

// Coleção "produtos" no banco "catalogo".
// O _id é string (prod-001 ou UUID v4), nunca ObjectId (CONTRATOS.md, seção 2.2).
const produtoSchema = new mongoose.Schema(
  {
    _id: { type: String, required: true },
    nome: { type: String, required: true },
    descricao: { type: String, default: '' },
    precoCentavos: { type: Number, required: true },
    disponivel: { type: Boolean, default: true },
    criadoEm: { type: String, required: true },
  },
  { versionKey: false, collection: 'produtos' }
);

// Converte o documento do Mongo para o JSON do contrato (_id vira id).
function paraJson(doc) {
  return {
    id: doc._id,
    nome: doc.nome,
    descricao: doc.descricao ?? '',
    precoCentavos: doc.precoCentavos,
    disponivel: doc.disponivel,
    criadoEm: doc.criadoEm,
  };
}

const Produto = mongoose.model('Produto', produtoSchema);

module.exports = { Produto, paraJson };
