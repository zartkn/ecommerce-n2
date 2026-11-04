const { Produto } = require('./produto.model');
const { log } = require('./util');

// Dados do seed (CONTRATOS.md, seção 8).
const CRIADO_EM = '2026-11-01T00:00:00.000Z';

const PRODUTOS = [
  { _id: 'prod-001', nome: 'Teclado Mecânico ABNT2', descricao: 'Switch marrom, retroiluminado', precoCentavos: 34990, disponivel: true },
  { _id: 'prod-002', nome: 'Mouse Gamer sem Fio', descricao: '16000 DPI, bateria recarregável', precoCentavos: 18990, disponivel: true },
  { _id: 'prod-003', nome: 'Headset USB 7.1', descricao: 'Microfone removível', precoCentavos: 24990, disponivel: true },
  { _id: 'prod-004', nome: 'Monitor 27" QHD 165Hz', descricao: 'Painel IPS, 1ms', precoCentavos: 189990, disponivel: true },
  { _id: 'prod-005', nome: 'Webcam Full HD', descricao: '1080p, microfone embutido', precoCentavos: 29990, disponivel: false },
  { _id: 'prod-006', nome: 'Cabo HDMI 2.1 2m', descricao: 'Suporta 4K 120Hz', precoCentavos: 3990, disponivel: true },
];

// Upsert por _id com $setOnInsert: as 3 réplicas sobem juntas e cada uma roda o seed.
// Se o produto já existe, nada muda. Se duas réplicas tentam inserir o mesmo _id ao
// mesmo tempo, uma delas recebe E11000 e a gente ignora, porque o produto já está lá.
async function executarSeed() {
  for (const p of PRODUTOS) {
    const { _id, ...campos } = p;
    try {
      await Produto.updateOne(
        { _id },
        { $setOnInsert: { ...campos, criadoEm: CRIADO_EM } },
        { upsert: true }
      );
    } catch (e) {
      if (e && e.code === 11000) continue;
      throw e;
    }
  }
  log.info(`seed concluido produtos=${PRODUTOS.length}`);
}

module.exports = { executarSeed, PRODUTOS };
