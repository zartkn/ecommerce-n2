#!/usr/bin/env bash
# Roteiro da demonstração pelas APIs (passa sempre pelo Ingress).
#
#   ./scripts/demo.sh http://<hostname-do-load-balancer>    # EKS
#   ./scripts/demo.sh                                       # docker-compose (http://localhost)
#
# Pausa entre as etapas. Para rodar direto, sem pausa: SEM_PAUSA=1 ./scripts/demo.sh ...
export MSYS_NO_PATHCONV=1   # Git Bash no Windows: não converter argumentos que parecem caminho
set -uo pipefail

BASE="${1:-http://localhost}"
BASE="${BASE%/}"
JSON='Content-Type: application/json'

# Formata JSON se der; se a resposta não for JSON (erro do Load Balancer, por exemplo), mostra como veio
pretty() {
  local corpo; corpo=$(cat)
  if command -v jq >/dev/null 2>&1 && echo "$corpo" | jq . 2>/dev/null; then return; fi
  if command -v python3 >/dev/null 2>&1 && echo "$corpo" | python3 -m json.tool 2>/dev/null; then return; fi
  echo "$corpo"
}
titulo() { printf "\n\033[1;36m==== %s ====\033[0m\n" "$1"; }
pausa()  { [ -n "${SEM_PAUSA:-}" ] || read -r -p "   [enter para continuar] " _; }
id_de()  { sed -E 's/^\{"id":"([^"]+)".*/\1/'; }

titulo "1. Balanceamento: 10 chamadas para o Catálogo (3 réplicas) via Ingress"
for i in $(seq 1 10); do
  curl -s "$BASE/api/produtos/instance"; echo
done
pausa

titulo "2. Catálogo: produtos do seed"
curl -s "$BASE/api/produtos" | pretty
pausa

titulo "3. Caminho feliz: prod-001 x2 = R\$ 699,80 (limite R\$ 1.000)"
RESP=$(curl -s -X POST "$BASE/api/pedidos" -H "$JSON" \
  -d '{"produtoId":"prod-001","quantidade":2,"emailCliente":"cliente@email.com"}')
echo "$RESP" | pretty
PEDIDO1=$(echo "$RESP" | id_de)
echo "   -> pedido $PEDIDO1 nasceu PENDENTE. Pagamento processa em ~2 s pelo RabbitMQ..."
sleep 4
echo "   GET /api/pedidos/$PEDIDO1"
curl -s "$BASE/api/pedidos/$PEDIDO1" | pretty
echo "   GET /api/pagamentos/pedido/$PEDIDO1"
curl -s "$BASE/api/pagamentos/pedido/$PEDIDO1" | pretty
echo "   GET /api/notificacoes?pedidoId=$PEDIDO1"
curl -s "$BASE/api/notificacoes?pedidoId=$PEDIDO1" | pretty
pausa

titulo "4. Recusa por valor: prod-004 x1 = R\$ 1.899,90"
RESP=$(curl -s -X POST "$BASE/api/pedidos" -H "$JSON" \
  -d '{"produtoId":"prod-004","quantidade":1,"emailCliente":"cliente@email.com"}')
PEDIDO2=$(echo "$RESP" | id_de)
echo "$RESP" | pretty
sleep 4
curl -s "$BASE/api/pedidos/$PEDIDO2" | pretty
curl -s "$BASE/api/notificacoes?pedidoId=$PEDIDO2" | pretty
pausa

titulo "5. Recusa por quantidade: prod-002 x6 = R\$ 1.139,40"
RESP=$(curl -s -X POST "$BASE/api/pedidos" -H "$JSON" \
  -d '{"produtoId":"prod-002","quantidade":6,"emailCliente":"cliente@email.com"}')
PEDIDO3=$(echo "$RESP" | id_de)
sleep 4
curl -s "$BASE/api/pedidos/$PEDIDO3" | pretty
pausa

titulo "6. Erros do contrato"
echo "   produto indisponível (422):"
curl -s -X POST "$BASE/api/pedidos" -H "$JSON" -d '{"produtoId":"prod-005","quantidade":1,"emailCliente":"a@b.com"}' | pretty
echo "   produto inexistente (404):"
curl -s -X POST "$BASE/api/pedidos" -H "$JSON" -d '{"produtoId":"prod-999","quantidade":1,"emailCliente":"a@b.com"}' | pretty
echo "   quantidade inválida (400):"
curl -s -X POST "$BASE/api/pedidos" -H "$JSON" -d '{"produtoId":"prod-001","quantidade":0,"emailCliente":"a@b.com"}' | pretty
pausa

titulo "7. Visão geral"
echo "   pedidos:";      curl -s "$BASE/api/pedidos" | pretty
echo "   pagamentos:";   curl -s "$BASE/api/pagamentos" | pretty
echo "   notificações:"; curl -s "$BASE/api/notificacoes" | pretty

echo
echo "Fim. Evidências do cluster: ./scripts/evidencias-k8s.sh"
