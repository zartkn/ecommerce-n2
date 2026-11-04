"""Utilitários: logs no formato do contrato, datas, dinheiro e corpo de erro."""
import logging
import sys
from datetime import datetime, timezone

from fastapi.responses import JSONResponse

logging.addLevelName(logging.WARNING, "WARN")

log = logging.getLogger("notificacao")
log.setLevel(logging.INFO)
log.propagate = False
_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(logging.Formatter("[notificacao] %(levelname)s %(message)s"))
log.addHandler(_handler)


def agora() -> str:
    """ISO 8601 em UTC com milissegundos e Z (seção 2.4)."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def formatar_reais(centavos: int) -> str:
    """69980 -> '699,80' e 189990 -> '1.899,90' (sem float)."""
    reais, cent = divmod(int(centavos), 100)
    return f"{reais:,}".replace(",", ".") + f",{cent:02d}"


def erro(status: int, codigo: str, mensagem: str) -> JSONResponse:
    """Corpo de erro padrão (seção 2.5)."""
    return JSONResponse(
        status_code=status,
        content={"erro": codigo, "mensagem": mensagem, "timestamp": agora()},
    )
