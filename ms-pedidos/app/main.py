"""Microsserviço de Pedidos (Python + FastAPI + MySQL).

Responsável: Edmund. Orquestra o checkout:
1. valida o produto no Catálogo via REST (Service Discovery)
2. salva o pedido PENDENTE no próprio MySQL
3. publica pedido.criado no RabbitMQ
4. consome pagamento.* e atualiza o status para PAGO ou RECUSADO
"""
import asyncio
import os
import uuid
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, ConfigDict, Field, StrictInt, StrictStr, field_validator

from . import catalogo_client, config, db, messaging
from .util import ErroApi, agora, erro, log


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        await asyncio.to_thread(db.inicializar_banco)
        await messaging.conectar()
    except Exception as e:  # noqa: BLE001
        # Contrato (2.7): não conseguiu subir, encerra com código 1 e o Kubernetes reinicia o Pod
        log.error(f"falha na inicializacao detalhe=\"{e}\"")
        os._exit(1)
    log.info(f"servico iniciado porta={config.PORT} pod={config.POD_NAME}")
    yield
    await messaging.fechar()
    await catalogo_client.fechar()


app = FastAPI(
    title="ms-pedidos",
    version="1.0.0",
    description="Pedidos do e-commerce N2. Valida no Catálogo (REST) e publica pedido.criado (RabbitMQ).",
    docs_url="/api/pedidos/docs",
    openapi_url="/api/pedidos/openapi.json",
    redoc_url=None,
    lifespan=lifespan,
)


# ---------- Middleware e tratamento de erros ----------

@app.middleware("http")
async def header_pod(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Pod-Name"] = config.POD_NAME
    return response


@app.exception_handler(ErroApi)
async def tratar_erro_api(request: Request, exc: ErroApi):
    return erro(exc.status, exc.codigo, exc.mensagem)


@app.exception_handler(RequestValidationError)
async def tratar_validacao(request: Request, exc: RequestValidationError):
    # O FastAPI devolveria 422 com "detail". O contrato pede 400 DADOS_INVALIDOS.
    partes = []
    for e in exc.errors():
        campo = ".".join(str(p) for p in e.get("loc", []) if p != "body")
        partes.append(f"{campo or 'corpo'}: {e.get('msg')}")
    return erro(400, "DADOS_INVALIDOS", "; ".join(partes) or "Dados inválidos")


@app.exception_handler(Exception)
async def tratar_inesperado(request: Request, exc: Exception):
    log.error(f"erro nao tratado path={request.url.path} detalhe=\"{exc}\"")
    resp = erro(500, "ERRO_INTERNO", "Erro interno no serviço de pedidos")
    resp.headers["X-Pod-Name"] = config.POD_NAME
    return resp


# ---------- Modelos de entrada ----------

class CriarPedido(BaseModel):
    model_config = ConfigDict(extra="ignore")

    produtoId: Annotated[StrictStr, Field(min_length=1, max_length=36)]
    quantidade: Annotated[StrictInt, Field(ge=1, le=10)]
    emailCliente: Annotated[StrictStr, Field(min_length=3, max_length=200)]

    @field_validator("produtoId")
    @classmethod
    def produto_nao_vazio(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("produtoId não pode ser vazio")
        return v.strip()

    @field_validator("emailCliente")
    @classmethod
    def email_com_arroba(cls, v: str) -> str:
        if "@" not in v:
            raise ValueError("emailCliente deve conter @")
        return v.strip()


# ---------- Rotas ----------

@app.get("/health", include_in_schema=False)
async def health():
    return {"status": "UP", "servico": config.SERVICO, "pod": config.POD_NAME}


@app.post("/api/pedidos", status_code=201)
async def criar_pedido(body: CriarPedido):
    # 1 e 2. Valida o produto no Catálogo (404, 503 e 422 saem como ErroApi)
    produto = await catalogo_client.buscar_produto(body.produtoId)
    if not produto.get("disponivel", False):
        raise ErroApi(422, "PRODUTO_INDISPONIVEL", f"Produto {body.produtoId} está indisponível")

    # 3. Calcula o total em centavos (só inteiros, nada de float)
    preco = int(produto["precoCentavos"])
    total = preco * body.quantidade

    # 4. Salva PENDENTE e faz commit antes de publicar
    momento = agora()
    pedido = db.PedidoDB(
        id=str(uuid.uuid4()),
        produto_id=produto["id"],
        nome_produto=produto["nome"],
        preco_unitario_centavos=preco,
        quantidade=body.quantidade,
        valor_total_centavos=total,
        email_cliente=body.emailCliente,
        status="PENDENTE",
        motivo_recusa=None,
        criado_em=momento,
        atualizado_em=momento,
    )
    await asyncio.to_thread(db.inserir, pedido)
    log.info(f"pedido criado id={pedido.id} valorTotalCentavos={total}")

    # 5 e 6. Publica. Se falhar, desfaz o pedido e devolve 503.
    try:
        await messaging.publicar_pedido_criado(pedido)
    except Exception as e:  # noqa: BLE001
        log.error(f"falha ao publicar evento pedidoId={pedido.id} detalhe=\"{e.__class__.__name__}: {e}\"")
        await asyncio.to_thread(db.apagar, pedido.id)
        raise ErroApi(503, "MENSAGERIA_INDISPONIVEL", "Não foi possível publicar o pedido na mensageria")

    return pedido.para_json()


@app.get("/api/pedidos")
async def listar_pedidos():
    pedidos = await asyncio.to_thread(db.listar)
    return [p.para_json() for p in pedidos]


@app.get("/api/pedidos/{pedido_id}")
async def buscar_pedido(pedido_id: str):
    pedido = await asyncio.to_thread(db.buscar, pedido_id)
    if pedido is None:
        raise ErroApi(404, "PEDIDO_NAO_ENCONTRADO", f"Pedido {pedido_id} não encontrado")
    return pedido.para_json()
