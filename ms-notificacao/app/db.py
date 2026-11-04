"""Persistência no MongoDB próprio do Notificação (Database per Service)."""
import asyncio
from typing import Optional

from pymongo import ASCENDING, DESCENDING, AsyncMongoClient

from . import config
from .util import log

_client: Optional[AsyncMongoClient] = None
_colecao = None


async def conectar() -> None:
    """Conecta com retry (seção 2.7) e cria o índice único de idempotência."""
    global _client, _colecao
    for tentativa in range(1, config.RETRY_TENTATIVAS + 1):
        try:
            _client = AsyncMongoClient(config.MONGO_URL, serverSelectionTimeoutMS=4000)
            await _client.admin.command("ping")
            banco = _client.get_default_database(default="notificacao")
            _colecao = banco["notificacoes"]
            # Índice único: o mesmo pedido não recebe duas notificações do mesmo tipo
            await _colecao.create_index(
                [("pedidoId", ASCENDING), ("tipo", ASCENDING)],
                unique=True,
                name="uk_pedido_tipo",
            )
            log.info(f"mongo conectado url={config.MONGO_URL}")
            return
        except Exception as e:  # noqa: BLE001
            log.warning(
                f"mongo indisponivel tentativa={tentativa}/{config.RETRY_TENTATIVAS} detalhe=\"{e.__class__.__name__}\""
            )
            if _client is not None:
                await _client.close()
            await asyncio.sleep(config.RETRY_INTERVALO_S)
    raise RuntimeError("nao foi possivel conectar no mongo")


def para_json(doc: dict) -> dict:
    """Documento do Mongo -> JSON do contrato (_id vira id)."""
    return {
        "id": doc["_id"],
        "pedidoId": doc["pedidoId"],
        "emailCliente": doc["emailCliente"],
        "tipo": doc["tipo"],
        "canal": doc["canal"],
        "mensagem": doc["mensagem"],
        "eventId": doc["eventId"],
        "criadoEm": doc["criadoEm"],
    }


async def inserir(doc: dict) -> None:
    """Lança DuplicateKeyError se já existir notificação para (pedidoId, tipo)."""
    await _colecao.insert_one(doc)


async def listar(pedido_id: Optional[str] = None) -> list[dict]:
    filtro = {"pedidoId": pedido_id} if pedido_id else {}
    cursor = _colecao.find(filtro).sort("criadoEm", DESCENDING)
    return [para_json(d) async for d in cursor]


async def buscar(notificacao_id: str) -> Optional[dict]:
    doc = await _colecao.find_one({"_id": notificacao_id})
    return para_json(doc) if doc else None


async def fechar() -> None:
    if _client is not None:
        await _client.close()
