const mongoose = require('mongoose');
const config = require('./config');
const app = require('./app');
const { executarSeed } = require('./seed');
const { log, esperar } = require('./util');

// Tenta conectar no Mongo a cada 5 s, até 24 vezes (CONTRATOS.md, seção 2.7).
async function conectarMongo() {
  for (let tentativa = 1; tentativa <= config.retry.tentativas; tentativa++) {
    try {
      await mongoose.connect(config.mongoUrl, { serverSelectionTimeoutMS: 4000 });
      log.info(`mongo conectado url=${config.mongoUrl}`);
      return;
    } catch (e) {
      log.warn(`mongo indisponivel tentativa=${tentativa}/${config.retry.tentativas} detalhe="${e.message}"`);
      await esperar(config.retry.intervaloMs);
    }
  }
  log.error('nao foi possivel conectar no mongo, encerrando');
  process.exit(1);
}

async function iniciar() {
  await conectarMongo();
  if (config.seedOnStart) await executarSeed();

  const server = app.listen(config.port, () => {
    log.info(`servico iniciado porta=${config.port} pod=${config.podName}`);
  });

  // O Kubernetes manda SIGTERM antes de matar o Pod.
  const encerrar = () => {
    log.info('encerrando servico');
    server.close(() => mongoose.disconnect().finally(() => process.exit(0)));
    setTimeout(() => process.exit(0), 5000).unref();
  };
  process.on('SIGTERM', encerrar);
  process.on('SIGINT', encerrar);
}

iniciar().catch((e) => {
  log.error(`falha na inicializacao detalhe="${e.message}"`);
  process.exit(1);
});
