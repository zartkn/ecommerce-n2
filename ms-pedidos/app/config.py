"""Configuração lida das variáveis de ambiente (CONTRATOS.md, seção 9)."""
import os
import socket

SERVICO = "pedidos"
POD_NAME = os.getenv("HOSTNAME") or socket.gethostname()

PORT = int(os.getenv("PORT", "8000"))

DB_HOST = os.getenv("DB_HOST", "mysql-pedidos")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_NAME = os.getenv("DB_NAME", "pedidos")
DB_USER = os.getenv("DB_USER", "pedidos")
DB_PASSWORD = os.getenv("DB_PASSWORD", "pedidos123")

CATALOGO_URL = os.getenv("CATALOGO_URL", "http://catalogo:3000").rstrip("/")
CATALOGO_TIMEOUT_MS = int(os.getenv("CATALOGO_TIMEOUT_MS", "3000"))

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "ecommerce")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "ecommerce123")
RABBITMQ_EXCHANGE = os.getenv("RABBITMQ_EXCHANGE", "ecommerce.eventos")

# Topologia fixa do contrato (seção 7.4)
FILA_CONSUMO = "pedidos.resultado-pagamento"
BINDING_CONSUMO = "pagamento.*"
ROUTING_KEY_PEDIDO_CRIADO = "pedido.criado"

# Retry na subida (seção 2.7)
RETRY_INTERVALO_S = 5
RETRY_TENTATIVAS = 24
