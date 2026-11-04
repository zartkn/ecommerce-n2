"""Microsserviço de Notificação (Python + FastAPI + MongoDB).

Responsável: Mickael. Consome o resultado do pagamento no RabbitMQ, grava a
notificação no próprio Mongo (com idempotência) e simula o envio de e-mail no log.
"""
import os
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Query, Request
from fastapi.exceptions import RequestValidationError

from . import config, db, messaging
from .util import erro, log


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        await db.conectar()
        await messaging.conectar()
    except Exception as e:  # noqa: BLE001
        log.error(f"falha na inicializacao detalhe=\"{e}\"")
        os._exit(1)
    log.info(f"servico iniciado porta={config.PORT} pod={config.POD_NAME}")
    yield
    await messaging.fechar()
    await db.fechar()


app = FastAPI(
    title="ms-notificacao",
    version="1.0.0",
    description="Notificações do e-commerce N2. Consome pagamento.* do RabbitMQ.",
    docs_url="/api/notificacoes/docs",
    openapi_url="/api/notificacoes/openapi.json",
    redoc_url=None,
    lifespan=lifespan,
)


@app.middleware("http")
async def header_pod(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Pod-Name"] = config.POD_NAME
    return response


@app.exception_handler(RequestValidationError)
async def tratar_validacao(request: Request, exc: RequestValidationError):
    return erro(400, "DADOS_INVALIDOS", "Parâmetros inválidos")


@app.exception_handler(Exception)
async def tratar_inesperado(request: Request, exc: Exception):
    log.error(f"erro nao tratado path={request.url.path} detalhe=\"{exc}\"")
    resp = erro(500, "ERRO_INTERNO", "Erro interno no serviço de notificação")
    resp.headers["X-Pod-Name"] = config.POD_NAME
    return resp


@app.get("/health", include_in_schema=False)
async def health():
    return {"status": "UP", "servico": config.SERVICO, "pod": config.POD_NAME}


@app.get("/api/notificacoes")
async def listar_notificacoes(pedidoId: Optional[str] = Query(default=None)):
    return await db.listar(pedidoId)


@app.get("/api/notificacoes/{notificacao_id}")
async def buscar_notificacao(notificacao_id: str):
    doc = await db.buscar(notificacao_id)
    if doc is None:
        return erro(404, "NOTIFICACAO_NAO_ENCONTRADA", f"Notificação {notificacao_id} não encontrada")
    return doc
