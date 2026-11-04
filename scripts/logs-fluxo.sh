#!/usr/bin/env bash
# Segundo terminal da apresentação: logs ao vivo do fluxo inteiro, com o nome do Pod.
# Mostra a chamada REST chegando no Catálogo, o pedido.criado saindo, o Pagamento
# consumindo e publicando, e o Notificação com o [EMAIL SIMULADO].
#
#   ./scripts/logs-fluxo.sh
#
# Abrir DEPOIS do preflight (o kubectl logs -f não acompanha Pods criados depois).
export MSYS_NO_PATHCONV=1

kubectl logs -f --prefix --since=5s --max-log-requests=12 \
  -l 'app in (catalogo,pedidos,pagamento,notificacao)' \
  | grep --line-buffered -vE 'GET /health|Uvicorn running|Waiting for application|Application startup|Started server'
