"""RabbitMQ: consome pagamento.aprovado e pagamento.recusado (CONTRATOS.md, seção 7)."""
import asyncio
import json
import uuid
from typing import Optional

import aio_pika
from aio_pika.abc import AbstractIncomingMessage
from pymongo.errors import DuplicateKeyError

from . import config, db
from .util import agora, formatar_reais, log

_conexao: Optional[aio_pika.abc.AbstractRobustConnection] = None

# routing key -> (tipo da notificação, texto)
TIPOS = {
    "pagamento.aprovado": (
        "PAGAMENTO_APROVADO",
        "Seu pagamento de R$ {valor} foi aprovado. Seu pedido já está sendo separado.",
    ),
    "pagamento.recusado": (
        "PAGAMENTO_RECUSADO",
        "Seu pagamento de R$ {valor} foi recusado (limite excedido). Tente novamente com outro valor.",
    ),
}


async def conectar() -> None:
    """Conecta com retry (seção 2.7), declara exchange, fila e binding e começa a consumir."""
    global _conexao
    for tentativa in range(1, config.RETRY_TENTATIVAS + 1):
        try:
            _conexao = await aio_pika.connect_robust(
                host=config.RABBITMQ_HOST,
                port=config.RABBITMQ_PORT,
                login=config.RABBITMQ_USER,
                password=config.RABBITMQ_PASSWORD,
                client_properties={"connection_name": f"notificacao@{config.POD_NAME}"},
            )
            break
        except Exception as e:  # noqa: BLE001
            log.warning(
                f"rabbitmq indisponivel tentativa={tentativa}/{config.RETRY_TENTATIVAS} detalhe=\"{e.__class__.__name__}\""
            )
            await asyncio.sleep(config.RETRY_INTERVALO_S)
    else:
        raise RuntimeError("nao foi possivel conectar no rabbitmq")

    log.info(f"rabbitmq conectado host={config.RABBITMQ_HOST}")

    canal = await _conexao.channel()
    await canal.set_qos(prefetch_count=1)
    exchange = await canal.declare_exchange(
        config.RABBITMQ_EXCHANGE, aio_pika.ExchangeType.TOPIC, durable=True, auto_delete=False
    )
    fila = await canal.declare_queue(
        config.FILA_CONSUMO, durable=True, exclusive=False, auto_delete=False
    )
    await fila.bind(exchange, routing_key=config.BINDING_CONSUMO)
    await fila.consume(_processar, no_ack=False)
    log.info(f"consumidor iniciado fila={config.FILA_CONSUMO} binding={config.BINDING_CONSUMO}")


async def _processar(msg: AbstractIncomingMessage) -> None:
    # 1. Lê e valida o envelope. Inválido: descarta (seção 7.7)
    try:
        envelope = json.loads(msg.body.decode("utf-8"))
        tipo_evento = envelope["tipo"]
        event_id = envelope["eventId"]
        dados = envelope["dados"]
        pedido_id = dados["pedidoId"]
        email = dados["emailCliente"]
        valor = int(dados["valorCentavos"])
        if tipo_evento not in TIPOS:
            raise ValueError(f"tipo inesperado {tipo_evento}")
    except Exception as e:  # noqa: BLE001
        log.error(f"mensagem invalida descartada detalhe=\"{e}\"")
        await msg.nack(requeue=False)
        return

    log.info(f"evento recebido tipo={tipo_evento} eventId={event_id} pedidoId={pedido_id}")

    tipo, modelo = TIPOS[tipo_evento]
    texto = modelo.format(valor=formatar_reais(valor))
    doc = {
        "_id": str(uuid.uuid4()),
        "pedidoId": pedido_id,
        "emailCliente": email,
        "tipo": tipo,
        "canal": "EMAIL_SIMULADO",
        "mensagem": texto,
        "eventId": event_id,
        "criadoEm": agora(),
    }

    try:
        # 2. Grava. Duplicado (E11000) não é erro: ignora e confirma.
        try:
            await db.inserir(doc)
        except DuplicateKeyError:
            log.warning(f"notificacao duplicada ignorada pedidoId={pedido_id} tipo={tipo}")
            await msg.ack()
            return

        # 3. "Envia" o e-mail (simulado no log)
        log.info(f"[EMAIL SIMULADO] para={email} mensagem=\"{texto}\"")

        # 4. Confirma
        await msg.ack()
    except Exception as e:  # noqa: BLE001
        log.error(f"erro ao processar evento eventId={event_id} detalhe=\"{e}\"")
        await msg.nack(requeue=False)


def conectado() -> bool:
    return _conexao is not None and not _conexao.is_closed


async def fechar() -> None:
    if _conexao is not None:
        await _conexao.close()
