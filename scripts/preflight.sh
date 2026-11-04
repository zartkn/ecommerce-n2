#!/usr/bin/env bash
# Checagem completa antes da apresentação. Rodar 30 a 40 minutos antes e de novo 5 minutos antes.
#
#   ./scripts/preflight.sh
#   BASE=http://localhost:8080 ./scripts/preflight.sh     # plano B (port-forward)
#
# Não muda nada no cluster, a não ser voltar o catalogo para 3 réplicas se tiver ficado diferente.
set -uo pipefail
export MSYS_NO_PATHCONV=1

OK=0; FALHA=0
ok()    { printf "  \033[1;32m[OK]\033[0m    %s\n" "$1"; OK=$((OK+1)); }
falha() { printf "  \033[1;31m[FALHA]\033[0m %s\n" "$1"; [ -n "${2:-}" ] && printf "          -> %s\n" "$2"; FALHA=$((FALHA+1)); }
campo() { local v; v=$(sed -E "s/.*\"$1\":\"?([^\",}]*)\"?.*/\1/"); printf '%s\n' "$v"; }   # extrai um campo simples do JSON (sempre com quebra de linha)

echo "== Cluster"
if kubectl get nodes >/dev/null 2>&1; then ok "kubectl conectado ao cluster"
else
  falha "kubectl não conecta" "credenciais do lab expiraram? copie o AWS Details e rode: aws eks update-kubeconfig --region us-east-1 --name ecommerce-n2"
  echo; echo "Sem acesso ao cluster, o resto não dá para checar."; exit 1
fi

PRONTOS=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')
if [ "$PRONTOS" -ge 2 ]; then ok "$PRONTOS nós Ready"
else falha "só $PRONTOS nó(s) Ready" "nós voltando do lab? espere 5 min; se continuar, EC2 > Instances > Start"; fi

echo "== Deployments"
for d in rabbitmq mongo-catalogo mongo-notificacao mysql-pedidos mysql-pagamento catalogo pedidos pagamento notificacao; do
  linha=$(kubectl get deploy "$d" -o jsonpath='{.spec.replicas} {.status.readyReplicas}' 2>/dev/null)
  desejado=${linha%% *}; prontos=${linha#* }
  [ "$prontos" = "$desejado" ] 2>/dev/null && [ -n "$desejado" ] \
    && ok "$d $prontos/$desejado" \
    || falha "$d ${prontos:-0}/${desejado:-?}" "kubectl describe deploy $d   |   kubectl logs deploy/$d --tail=30"
done

RC=$(kubectl get deploy catalogo -o jsonpath='{.spec.replicas}' 2>/dev/null)
if [ "$RC" != "3" ]; then
  echo "  catalogo está com $RC réplicas, voltando para 3..."
  kubectl scale deployment catalogo --replicas=3 >/dev/null && kubectl rollout status deployment/catalogo --timeout=120s >/dev/null \
    && ok "catalogo de volta a 3 réplicas" || falha "não consegui voltar o catalogo para 3"
fi

echo "== Ingress e Load Balancer"
BASE="${BASE:-}"
if [ -z "$BASE" ]; then
  LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$LB" ] && BASE="http://$LB"
fi
if [ -z "$BASE" ]; then
  falha "Load Balancer sem hostname" "plano B: kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80  e  BASE=http://localhost:8080"
  echo; printf "Resultado: %s OK, %s FALHA\n" "$OK" "$FALHA"; exit 1
fi
BASE="${BASE%/}"

for rota in produtos pedidos pagamentos notificacoes; do
  cod=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE/api/$rota")
  [ "$cod" = "200" ] && ok "GET /api/$rota -> 200" || falha "GET /api/$rota -> $cod" "DNS do LB ainda propagando? Pod do serviço Ready?"
done

DIST=$(for i in $(seq 1 12); do curl -s --max-time 5 "$BASE/api/produtos/instance" | campo pod; done | sort -u | grep -c .)
[ "$DIST" -ge 3 ] && ok "balanceamento: 12 chamadas caíram em $DIST Pods diferentes" \
                  || falha "balanceamento: só $DIST Pod(s) responderam" "kubectl get pods -l app=catalogo"

echo "== RabbitMQ"
FILAS=$(kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_queues name consumers 2>/dev/null)
for f in pagamento.pedido-criado pedidos.resultado-pagamento notificacao.resultado-pagamento; do
  c=$(echo "$FILAS" | awk -v f="$f" '$1==f {print $2}')
  [ "${c:-0}" -ge 1 ] 2>/dev/null && ok "fila $f com $c consumidor(es)" \
                               || falha "fila $f sem consumidor" "o serviço dono da fila está Running? kubectl rollout restart deploy/<servico>"
done

echo "== Fluxo de ponta a ponta (pedido de teste)"
RESP=$(curl -s --max-time 10 -X POST "$BASE/api/pedidos" -H 'Content-Type: application/json' \
  -d '{"produtoId":"prod-006","quantidade":1,"emailCliente":"preflight@email.com"}')
ID=$(echo "$RESP" | campo id)
if [ -z "$ID" ] || [ "$ID" = "$RESP" ]; then
  falha "POST /api/pedidos não criou pedido" "resposta: $RESP"
else
  ok "pedido $ID criado"
  ST=""
  for i in $(seq 1 15); do
    ST=$(curl -s "$BASE/api/pedidos/$ID" | campo status)
    [ "$ST" = "PAGO" ] && break
    sleep 1
  done
  [ "$ST" = "PAGO" ] && ok "pedido virou PAGO pelo RabbitMQ" || falha "pedido ficou $ST" "kubectl logs deploy/pagamento --tail=30"
  N=$(curl -s "$BASE/api/notificacoes?pedidoId=$ID" | grep -o '"tipo"' | wc -l | tr -d ' ')
  [ "$N" -ge 1 ] && ok "notificação registrada" || falha "sem notificação" "kubectl logs deploy/notificacao --tail=30"
fi

echo
if [ "$FALHA" -eq 0 ]; then
  printf "\033[1;32mTUDO PRONTO: %s checagens OK.\033[0m URL: %s\n" "$OK" "$BASE"
  echo "Agora: abrir ./scripts/logs-fluxo.sh em outro terminal e o painel do RabbitMQ."
else
  printf "\033[1;31m%s FALHA(S)\033[0m e %s OK. Corrigir antes de começar.\n" "$FALHA" "$OK"
  exit 1
fi
