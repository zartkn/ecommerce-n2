#!/usr/bin/env bash
# Roteiro de 5 minutos da apresentação (detalhes em APRESENTACAO.md).
#
#   ./scripts/apresentacao.sh              # os 4 blocos, com Enter entre eles
#   ./scripts/apresentacao.sh 2            # só um bloco (1, 2, 3 ou 4)
#   ./scripts/apresentacao.sh fila         # extras, se sobrar tempo ou o professor pedir:
#                                          #   fila | healing | discovery | bancos | rabbit
#
# Antes de começar: ./scripts/preflight.sh  e, em outro terminal, ./scripts/logs-fluxo.sh
# URL: descobre o Load Balancer sozinho. No plano B: BASE=http://localhost:8080 ./scripts/apresentacao.sh
set -uo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash no Windows: não converter argumentos que parecem caminho

# ---------- URL de entrada (sempre pelo Ingress) ----------
BASE="${BASE:-}"
if [ -z "$BASE" ]; then
  LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$LB" ] && BASE="http://$LB"
fi
if [ -z "$BASE" ]; then
  echo "Não achei o Load Balancer. Use o plano B:"
  echo "  kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80"
  echo "  BASE=http://localhost:8080 ./scripts/apresentacao.sh"
  exit 1
fi
BASE="${BASE%/}"
JSON='Content-Type: application/json'

# ---------- Visual ----------
CIANO='\033[1;36m'; AMARELO='\033[1;33m'; VERDE='\033[1;32m'; NORMAL='\033[0m'
bloco()  { printf "\n${CIANO}==================== %s ====================${NORMAL}\n" "$1"; }
nota()   { printf "${VERDE}>> %s${NORMAL}\n" "$1"; }
run()    { printf "${AMARELO}\$ %s${NORMAL}\n" "$1"; eval "$1"; echo; }
pausa()  { [ -n "${SEM_PAUSA:-}" ] || read -r -p "" _; }

pretty() {
  local corpo; corpo=$(cat)
  if command -v jq >/dev/null 2>&1 && echo "$corpo" | jq . 2>/dev/null; then return; fi
  if command -v python3 >/dev/null 2>&1 && echo "$corpo" | python3 -m json.tool 2>/dev/null; then return; fi
  if command -v python  >/dev/null 2>&1 && echo "$corpo" | python  -m json.tool 2>/dev/null; then return; fi
  echo "$corpo"
}
campo() { local v; v=$(sed -E "s/.*\"$1\":\"?([^\",}]*)\"?.*/\1/"); printf '%s\n' "$v"; }   # extrai um campo simples do JSON (sempre com quebra de linha)

# Chama o Catálogo N vezes pelo Ingress e mostra qual Pod respondeu cada uma
quem_respondeu() {
  printf "${AMARELO}\$ for i in \$(seq 1 %s); do curl -s %s/api/produtos/instance; done${NORMAL}\n" "$1" "$BASE"
  local pods
  pods=$(for i in $(seq 1 "$1"); do curl -s "$BASE/api/produtos/instance" | campo pod; done)
  echo "$pods" | awk '{printf "  %2d -> %s\n", NR, $0}'
  echo "  ---- respostas por Pod ----"
  echo "$pods" | sort | uniq -c | awk '{printf "  %s\t%s respostas\n", $2, $1}'
  echo
}

PODS_COLS='custom-columns=POD:.metadata.name,STATUS:.status.phase,IP:.status.podIP,NO:.spec.nodeName'

# ====================================================================
bloco_1() {
  bloco "1. APLICAÇÃO NO AMAZON EKS"
  run "kubectl get nodes -L node.kubernetes.io/instance-type"
  run "kubectl get deployments"
  run "kubectl get pods -o $PODS_COLS"
  run "kubectl get services"
  run "kubectl get ingress ecommerce-ingress"
  nota "Entrada externa: $BASE  (NGINX Ingress Controller atrás de um Load Balancer da AWS)"
}

bloco_2() {
  bloco "2. ESCALABILIDADE HORIZONTAL (catalogo)"
  run "kubectl get deployment catalogo"
  run "kubectl get pods -l app=catalogo -o $PODS_COLS"
  nota "3 réplicas atrás do mesmo Service. O Ingress distribui as requisições:"
  quem_respondeu 9

  nota "Escalando de 3 para 5 réplicas, ao vivo:"
  run "kubectl scale deployment catalogo --replicas=5"
  run "kubectl rollout status deployment/catalogo --timeout=120s"
  run "kubectl get pods -l app=catalogo -o $PODS_COLS"
  sleep 3   # tempo para o Ingress Controller atualizar a lista de endpoints
  nota "As réplicas novas já entram no balanceamento:"
  quem_respondeu 15

  nota "Voltando para 3 réplicas:"
  run "kubectl scale deployment catalogo --replicas=3"
  run "kubectl get deployment catalogo"
}

bloco_3() {
  bloco "3. DIVERSIDADE TECNOLÓGICA + DATABASE PER SERVICE"
  run "kubectl get deployments -o custom-columns='DEPLOYMENT:.metadata.name,IMAGEM:.spec.template.spec.containers[0].image,PRONTOS:.status.readyReplicas'"
  nota "Linguagem rodando dentro de cada Pod:"
  run "kubectl exec deploy/catalogo -- node --version"
  run "kubectl exec deploy/pedidos -- python --version"
  run "kubectl exec deploy/pagamento -- dotnet --list-runtimes"
  run "kubectl exec deploy/notificacao -- python --version"
}

bloco_4() {
  bloco "4. REST + MENSAGERIA RABBITMQ"
  run "kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_queues name consumers messages"

  nota "Pedido aprovado (R\$ 699,80): Pedidos consulta o Catálogo por REST e publica pedido.criado"
  printf "${AMARELO}\$ curl -X POST %s/api/pedidos -d '{\"produtoId\":\"prod-001\",\"quantidade\":2,...}'${NORMAL}\n" "$BASE"
  local resp id
  resp=$(curl -s -X POST "$BASE/api/pedidos" -H "$JSON" \
    -d '{"produtoId":"prod-001","quantidade":2,"emailCliente":"cliente@email.com"}')
  echo "$resp" | pretty
  id=$(echo "$resp" | campo id)
  echo
  nota "Status PENDENTE. Pagamento consome a fila e processa (olhar o terminal de logs)..."
  for s in 4 3 2 1; do printf "  %s " "$s"; sleep 1; done; echo; echo
  run "curl -s $BASE/api/pedidos/$id | pretty"
  run "curl -s $BASE/api/pagamentos/pedido/$id | pretty"
  run "curl -s '$BASE/api/notificacoes?pedidoId=$id' | pretty"

  nota "Pedido recusado (R\$ 1.899,90, acima do limite):"
  resp=$(curl -s -X POST "$BASE/api/pedidos" -H "$JSON" \
    -d '{"produtoId":"prod-004","quantidade":1,"emailCliente":"cliente@email.com"}')
  id=$(echo "$resp" | campo id)
  printf "  pedido %s criado como %s\n" "$id" "$(echo "$resp" | campo status)"
  sleep 4
  printf "  4 s depois: %s (%s)\n\n" \
    "$(curl -s "$BASE/api/pedidos/$id" | campo status)" \
    "$(curl -s "$BASE/api/pedidos/$id" | campo motivoRecusa)"
}

# ---------- Extras, só se o professor pedir ----------
extra_healing() {
  bloco "EXTRA: AUTORRECUPERAÇÃO (o Deployment repõe o Pod apagado)"
  local pod
  pod=$(kubectl get pods -l app=catalogo -o jsonpath='{.items[0].metadata.name}')
  run "kubectl delete pod $pod --wait=false"
  sleep 4
  run "kubectl get pods -l app=catalogo -o $PODS_COLS"
}

extra_fila() {
  bloco "EXTRA: DESACOPLAMENTO (Pagamento fora do ar, a mensagem espera na fila)"
  run "kubectl scale deployment pagamento --replicas=0"
  run "kubectl wait --for=delete pod -l app=pagamento --timeout=90s"
  local resp id st
  resp=$(curl -s -X POST "$BASE/api/pedidos" -H "$JSON" \
    -d '{"produtoId":"prod-003","quantidade":1,"emailCliente":"cliente@email.com"}')
  id=$(echo "$resp" | campo id)
  nota "Pedido $id criado com o Pagamento desligado: $(echo "$resp" | campo status)"
  sleep 2
  run "kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_queues name consumers messages"
  nota "A fila pagamento.pedido-criado tem 1 mensagem e 0 consumidores. Ligando o Pagamento de novo:"
  run "kubectl scale deployment pagamento --replicas=1"
  run "kubectl rollout status deployment/pagamento --timeout=180s"
  for i in $(seq 1 30); do
    st=$(curl -s "$BASE/api/pedidos/$id" | campo status)
    [ "$st" = "PAGO" ] && break
    sleep 1
  done
  nota "Pedido $id agora está: $st (a mensagem que estava na fila foi consumida)"
}

extra_discovery() {
  bloco "EXTRA: SERVICE DISCOVERY (nome do Service, nunca IP de Pod)"
  run "kubectl get deploy pedidos -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\\n\"}{end}' | grep -E 'CATALOGO_URL|DB_HOST|RABBITMQ_HOST'"
  run "kubectl exec deploy/pedidos -- getent hosts catalogo"
  run "kubectl get service catalogo"
  run "kubectl exec deploy/pedidos -- python -c \"import urllib.request;print(urllib.request.urlopen('http://catalogo:3000/api/produtos/instance').read().decode())\""
}

extra_bancos() {
  bloco "EXTRA: ISOLAMENTO DOS BANCOS"
  run "kubectl exec deploy/mysql-pedidos -- sh -c 'mysql -upedidos -p\"\$MYSQL_PASSWORD\" pedidos -e \"SHOW TABLES\" 2>/dev/null'"
  run "kubectl exec deploy/mysql-pagamento -- sh -c 'mysql -upagamento -p\"\$MYSQL_PASSWORD\" pagamento -e \"SHOW TABLES\" 2>/dev/null'"
  run "kubectl exec deploy/mongo-catalogo -- mongosh catalogo --quiet --eval 'db.getCollectionNames()'"
  run "kubectl exec deploy/mongo-notificacao -- mongosh notificacao --quiet --eval 'db.getCollectionNames()'"
}

extra_rabbit() {
  bloco "EXTRA: TOPOLOGIA DO RABBITMQ"
  run "kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_exchanges name type durable | grep -E 'name|ecommerce'"
  run "kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_bindings source_name destination_name routing_key | grep ecommerce"
  run "kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_queues name consumers messages"
}

# ---------- Execução ----------
case "${1:-todos}" in
  1) bloco_1 ;;
  2) bloco_2 ;;
  3) bloco_3 ;;
  4) bloco_4 ;;
  healing)   extra_healing ;;
  fila)      extra_fila ;;
  discovery) extra_discovery ;;
  bancos)    extra_bancos ;;
  rabbit)    extra_rabbit ;;
  todos)
    bloco_1; pausa
    bloco_2; pausa
    bloco_3; pausa
    bloco_4
    nota "Fim da demonstração."
    ;;
  *) echo "uso: $0 [1|2|3|4|fila|healing|discovery|bancos|rabbit]"; exit 1 ;;
esac
