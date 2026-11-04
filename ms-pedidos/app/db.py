"""Persistência no MySQL próprio do Pedidos (Database per Service)."""
import time
from typing import Optional

from sqlalchemy import Integer, String, create_engine, delete, select, update
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from . import config
from .util import agora, log


class Base(DeclarativeBase):
    pass


class PedidoDB(Base):
    """Tabela "pedidos" (CONTRATOS.md, seção 4). Colunas em snake_case."""

    __tablename__ = "pedidos"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    produto_id: Mapped[str] = mapped_column(String(36), nullable=False)
    nome_produto: Mapped[str] = mapped_column(String(200), nullable=False)
    preco_unitario_centavos: Mapped[int] = mapped_column(Integer, nullable=False)
    quantidade: Mapped[int] = mapped_column(Integer, nullable=False)
    valor_total_centavos: Mapped[int] = mapped_column(Integer, nullable=False)
    email_cliente: Mapped[str] = mapped_column(String(200), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    motivo_recusa: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    criado_em: Mapped[str] = mapped_column(String(30), nullable=False)
    atualizado_em: Mapped[str] = mapped_column(String(30), nullable=False)

    def para_json(self) -> dict:
        """JSON do contrato em camelCase."""
        return {
            "id": self.id,
            "produtoId": self.produto_id,
            "nomeProduto": self.nome_produto,
            "precoUnitarioCentavos": self.preco_unitario_centavos,
            "quantidade": self.quantidade,
            "valorTotalCentavos": self.valor_total_centavos,
            "emailCliente": self.email_cliente,
            "status": self.status,
            "motivoRecusa": self.motivo_recusa,
            "criadoEm": self.criado_em,
            "atualizadoEm": self.atualizado_em,
        }


_url = (
    f"mysql+pymysql://{config.DB_USER}:{config.DB_PASSWORD}"
    f"@{config.DB_HOST}:{config.DB_PORT}/{config.DB_NAME}?charset=utf8mb4"
)
engine = create_engine(_url, pool_pre_ping=True, pool_recycle=1800)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def inicializar_banco() -> None:
    """Conecta com retry e cria a tabela se não existir (seção 2.7)."""
    for tentativa in range(1, config.RETRY_TENTATIVAS + 1):
        try:
            Base.metadata.create_all(engine)
            log.info(f"mysql conectado host={config.DB_HOST} banco={config.DB_NAME}")
            return
        except Exception as e:  # noqa: BLE001
            log.warning(
                f"mysql indisponivel tentativa={tentativa}/{config.RETRY_TENTATIVAS} detalhe=\"{e.__class__.__name__}\""
            )
            time.sleep(config.RETRY_INTERVALO_S)
    raise RuntimeError("nao foi possivel conectar no mysql")


# Funções síncronas: as rotas chamam via asyncio.to_thread para não travar o event loop.

def inserir(pedido: PedidoDB) -> PedidoDB:
    with SessionLocal() as s:
        s.add(pedido)
        s.commit()
        return pedido


def apagar(pedido_id: str) -> None:
    with SessionLocal() as s:
        s.execute(delete(PedidoDB).where(PedidoDB.id == pedido_id))
        s.commit()


def listar() -> list[PedidoDB]:
    with SessionLocal() as s:
        return list(s.scalars(select(PedidoDB).order_by(PedidoDB.criado_em.desc())))


def buscar(pedido_id: str) -> Optional[PedidoDB]:
    with SessionLocal() as s:
        return s.get(PedidoDB, pedido_id)


def atualizar_resultado(pedido_id: str, status: str, motivo_recusa: Optional[str]) -> str:
    """Atualiza o pedido com o resultado do pagamento.

    Só altera se o pedido ainda estiver PENDENTE (idempotência).
    Retorna "ATUALIZADO", "JA_PROCESSADO" ou "NAO_ENCONTRADO".
    """
    with SessionLocal() as s:  # type: Session
        res = s.execute(
            update(PedidoDB)
            .where(PedidoDB.id == pedido_id, PedidoDB.status == "PENDENTE")
            .values(status=status, motivo_recusa=motivo_recusa, atualizado_em=agora())
        )
        s.commit()
        if res.rowcount == 1:
            return "ATUALIZADO"
        existe = s.get(PedidoDB, pedido_id) is not None
        return "JA_PROCESSADO" if existe else "NAO_ENCONTRADO"
