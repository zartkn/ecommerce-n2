// Configuração lida das variáveis de ambiente (CONTRATOS.md, seção 9).
// Os valores padrão funcionam no docker-compose e no Kubernetes sem mudar nada.
const os = require('os');

module.exports = {
  servico: 'catalogo',
  port: parseInt(process.env.PORT || '3000', 10),
  mongoUrl: process.env.MONGO_URL || 'mongodb://mongo-catalogo:27017/catalogo',
  seedOnStart: (process.env.SEED_ON_START || 'true').toLowerCase() === 'true',
  // No Kubernetes, HOSTNAME é o nome do Pod.
  podName: process.env.HOSTNAME || os.hostname(),
  retry: {
    intervaloMs: 5000,
    tentativas: 24,
  },
};
