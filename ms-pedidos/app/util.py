"""Utilitários: logs no formato do contrato, datas ISO 8601 e corpo de erro."""
import logging
import sys
from datetime import datetime, timezone

from fastapi.responses import JSONResponse

# O contrato usa WARN, e não WARNING
logging.addLevelName(logging.WARNING, "WARN")

log = logging.getLogger("pedidos")
log.setLevel(logging.INFO)
log.propagate = False
_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(logging.Formatter("[pedidos] %(levelname)s %(message)s"))
log.addHandler(_handler)


def agora() -> str:
    """ISO 8601 em UTC com milissegundos e Z (seção 2.4)."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def erro(status: int, codigo: str, mensagem: str) -> JSONResponse:
    """Corpo de erro padrão (seção 2.5)."""
    return JSONResponse(
        status_code=status,
        content={"erro": codigo, "mensagem": mensagem, "timestamp": agora()},
    )


class ErroApi(Exception):
    """Exceção de negócio que vira o JSON de erro do contrato."""

    def __init__(self, status: int, codigo: str, mensagem: str):
        super().__init__(mensagem)
        self.status = status
        self.codigo = codigo
        self.mensagem = mensagem
