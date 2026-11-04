// Logs no formato do contrato: [servico] NIVEL mensagem chave=valor
const log = {
  info: (msg) => console.log(`[catalogo] INFO ${msg}`),
  warn: (msg) => console.warn(`[catalogo] WARN ${msg}`),
  error: (msg) => console.error(`[catalogo] ERROR ${msg}`),
};

// ISO 8601 em UTC com milissegundos e Z
const agora = () => new Date().toISOString();

// Corpo de erro padrão (CONTRATOS.md, seção 2.5)
function erro(res, status, codigo, mensagem) {
  return res.status(status).json({ erro: codigo, mensagem, timestamp: agora() });
}

const esperar = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

module.exports = { log, agora, erro, esperar };
