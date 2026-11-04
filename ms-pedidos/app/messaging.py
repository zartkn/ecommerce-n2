"""RabbitMQ: publica pedido.criado e consome pagamento.* (CONTRATOS.md, seção 7)."""
import asyncio
import json
import uuid
from typing import Optional

import aio_pika
from aio_pika.abc import AbstractIncomingMessage

from . import config, db
from .util import agora, log

_conexao: Optional[aio_pika.abc.AbstractRobustConnection] = None
_canal_publicacao: Optional[aio_pika.abc.AbstractChannel] = None
_exchange_publicacao: Optional[aio_pika.abc.AbstractExchange] = None


async def _declarar_exchange(canal: aio_pika.abc.AbstractChannel) -> aio_pika.abc.AbstractExchange:
    # Parâmetros exatamente iguais aos da seção 7.2, senão dá PRECONDITION_FAILED
    return await canal.declare_exchange(
        config.RABBITMQ_EXCHANGE, aio_pika.ExchangeType.TOPIC, durable=True, auto_delete=False
    )


async def conectar() -> None:
    """Conecta com retry (seção 2.7), declara o exchange e inicia o consumidor."""
    global _conexao, _canal_publicacao, _exchange_publicacao

    for tentativa in range(1, config.RETRY_TENTATIVAS + 1):
        try:
            _conexao = await aio_pika.connect_robust(
                host=config.RABBITMQ_HOST,
                port=config.RABBITMQ_PORT,
                login=config.RABBITMQ_USER,
                password=config.RABBITMQ_PASSWORD,
                client_properties={"connection_name": f"pedidos@{config.POD_NAME}"},
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

    # Canal de publicação com confirmação do broker.
    # on_return_raises: se a mensagem não tiver nenhuma fila para ir (mandatory), vira erro
    # em vez de sumir em silêncio. Assim o POST devolve 503 e o pedido não fica órfão.
    _canal_publicacao = await _conexao.channel(publisher_confirms=True, on_return_raises=True)
    _exchange_publicacao = await _declarar_exchange(_canal_publicacao)

    await _iniciar_consumidor()


async def _iniciar_consumidor() -> None:
    canal = await _conexao.channel()
    await canal.set_qos(prefetch_count=1)
    exchange = await _declarar_exchange(canal)
    fila = await canal.declare_queue(
        config.FILA_CONSUMO, durable=True, exclusive=False, auto_delete=False
    )
    await fila.bind(exchange, routing_key=config.BINDING_CONSUMO)
    await fila.consume(_processar_resultado_pagamento, no_ack=False)
    log.info(f"consumidor iniciado fila={config.FILA_CONSUMO} binding={config.BINDING_CONSUMO}")


async def publicar_pedido_criado(pedido: db.PedidoDB) -> str:
    """Publica pedido.criado. Lança exceção se o broker não confirmar."""
    if _exchange_publicacao is None:
        raise RuntimeError("rabbitmq nao inicializado")

    event_id = str(uuid.uuid4())
    envelope = {
        "eventId": event_id,
        "tipo": config.ROUTING_KEY_PEDIDO_CRIADO,
        "origem": config.SERVICO,
        "ocorridoEm": agora(),
        "dados": {
            "pedidoId": pedido.id,
            "produtoId": pedido.produto_id,
            "nomeProduto": pedido.nome_produto,
            "quantidade": pedido.quantidade,
            "valorTotalCentavos": pedido.valor_total_centavos,
            "emailCliente": pedido.email_cliente,
        },
    }
    mensagem = aio_pika.Message(
        body=json.dumps(envelope, ensure_ascii=False).encode("utf-8"),
        content_type="application/json",
        content_encoding="utf-8",
        delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
        message_id=event_id,
        type=config.ROUTING_KEY_PEDIDO_CRIADO,
    )
    await _exchange_publicacao.publish(
        mensagem, routing_key=config.ROUTING_KEY_PEDIDO_CRIADO, mandatory=True, timeout=5
    )
    log.info(
        f"evento publicado tipo={config.ROUTING_KEY_PEDIDO_CRIADO} eventId={event_id} pedidoId={pedido.id}"
    )
    return event_id


async def _processar_resultado_pagamento(msg: AbstractIncomingMessage) -> None:
    """Consome pagamento.aprovado / pagamento.recusado e atualiza o status do pedido."""
    try:
        envelope = json.loads(msg.body.decode("utf-8"))
        tipo = envelope["tipo"]
        event_id = envelope["eventId"]
        dados = envelope["dados"]
        pedido_id = dados["pedidoId"]
        if tipo not in ("pagamento.aprovado", "pagamento.recusado"):
            raise ValueError(f"tipo inesperado {tipo}")
    except Exception as e:  # noqa: BLE001
        # JSON inválido ou campo faltando: descarta (seção 7.7)
        log.error(f"mensagem invalida descartada detalhe=\"{e}\"")
        await msg.nack(requeue=False)
        return

    log.info(f"evento recebido tipo={tipo} eventId={event_id} pedidoId={pedido_id}")

    try:
        if tipo == "pagamento.aprovado":
            novo_status, motivo = "PAGO", None
        else:
            novo_status, motivo = "RECUSADO", dados.get("motivoRecusa")

        resultado = await asyncio.to_thread(db.atualizar_resultado, pedido_id, novo_status, motivo)

        if resultado == "ATUALIZADO":
            log.info(f"pedido atualizado id={pedido_id} status={novo_status}")
        elif resultado == "JA_PROCESSADO":
            log.warning(f"evento duplicado ignorado pedidoId={pedido_id} eventId={event_id}")
        else:
            log.warning(f"pedido nao encontrado pedidoId={pedido_id} eventId={event_id}")

        await msg.ack()
    except Exception as e:  # noqa: BLE001
        log.error(f"erro ao processar evento eventId={event_id} detalhe=\"{e}\"")
        await msg.nack(requeue=False)


def conectado() -> bool:
    return _conexao is not None and not _conexao.is_closed


async def fechar() -> None:
    if _conexao is not None:
        await _conexao.close()
