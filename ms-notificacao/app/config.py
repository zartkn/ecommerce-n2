"""Configuração lida das variáveis de ambiente (CONTRATOS.md, seção 9)."""
import os
import socket

SERVICO = "notificacao"
POD_NAME = os.getenv("HOSTNAME") or socket.gethostname()

PORT = int(os.getenv("PORT", "8001"))

MONGO_URL = os.getenv("MONGO_URL", "mongodb://mongo-notificacao:27017/notificacao")

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "ecommerce")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "ecommerce123")
RABBITMQ_EXCHANGE = os.getenv("RABBITMQ_EXCHANGE", "ecommerce.eventos")

# Topologia fixa do contrato (seção 7.4)
FILA_CONSUMO = "notificacao.resultado-pagamento"
BINDING_CONSUMO = "pagamento.*"

# Retry na subida (seção 2.7)
RETRY_INTERVALO_S = 5
RETRY_TENTATIVAS = 24
