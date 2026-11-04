"""Cliente REST do Catálogo (comunicação síncrona + Service Discovery).

A URL usa o nome do Service do Kubernetes (http://catalogo:3000), nunca o IP de um Pod.
"""
import httpx

from . import config
from .util import ErroApi, log

# Sem keep-alive: cada chamada abre uma conexão nova, e o kube-proxy pode mandar
# para um Pod diferente. Com keep-alive, todas as chamadas iriam para o mesmo Pod
# e o log "pod=" não mostraria o balanceamento entre as 3 réplicas.
_client = httpx.AsyncClient(
    timeout=config.CATALOGO_TIMEOUT_MS / 1000,
    limits=httpx.Limits(max_keepalive_connections=0),
)


async def buscar_produto(produto_id: str) -> dict:
    url = f"{config.CATALOGO_URL}/api/produtos/{produto_id}"
    try:
        resp = await _client.get(url)
    except httpx.HTTPError as e:
        log.error(f"catalogo inacessivel url={url} detalhe=\"{e.__class__.__name__}\"")
        raise ErroApi(503, "CATALOGO_INDISPONIVEL", "Não foi possível consultar o catálogo")

    if resp.status_code == 404:
        raise ErroApi(404, "PRODUTO_NAO_ENCONTRADO", f"Produto {produto_id} não encontrado")
    if resp.status_code != 200:
        log.error(f"catalogo respondeu erro status={resp.status_code}")
        raise ErroApi(503, "CATALOGO_INDISPONIVEL", "Não foi possível consultar o catálogo")

    produto = resp.json()
    pod = resp.headers.get("X-Pod-Name", "desconhecido")
    log.info(f"catalogo consultado produtoId={produto_id} pod={pod}")
    return produto


async def fechar() -> None:
    await _client.aclose()
