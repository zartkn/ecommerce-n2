#!/usr/bin/env bash
# Evidências de infraestrutura para a banca (rubrica 2 e isolamento da rubrica 1).
#   ./scripts/evidencias-k8s.sh
export MSYS_NO_PATHCONV=1   # Git Bash no Windows: não converter argumentos que parecem caminho
set -uo pipefail

titulo() { printf "\n\033[1;36m==== %s ====\033[0m\n" "$1"; }
pausa()  { [ -n "${SEM_PAUSA:-}" ] || read -r -p "   [enter para continuar] " _; }

titulo "Cluster EKS: nós"
kubectl get nodes -o wide
pausa

titulo "Deployments, Pods (catalogo com 3 réplicas e IPs diferentes) e Services ClusterIP"
kubectl get deployments
kubectl get pods -o wide
kubectl get svc
pausa

titulo "Ingress: regras de path e Load Balancer do NGINX Ingress Controller"
kubectl get ingress ecommerce-ingress
kubectl describe ingress ecommerce-ingress | sed -n '/Rules:/,/Annotations:/p'
kubectl get svc -n ingress-nginx ingress-nginx-controller
pausa

titulo "Service Discovery: o Pedidos resolve 'catalogo' pelo DNS do Kubernetes"
echo "   variável no Deployment do pedidos:"
kubectl get deploy pedidos -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E "CATALOGO_URL|DB_HOST|RABBITMQ_HOST"
echo "   DNS de dentro do Pod do pedidos (aponta para o ClusterIP do Service, não para um Pod):"
kubectl exec deploy/pedidos -- getent hosts catalogo
kubectl get svc catalogo -o jsonpath='   ClusterIP do Service catalogo: {.spec.clusterIP}{"\n"}'
echo "   chamada REST interna pelo nome do Service (5 vezes):"
for i in 1 2 3 4 5; do
  kubectl exec deploy/pedidos -- python -c "import urllib.request;print(urllib.request.urlopen('http://catalogo:3000/api/produtos/instance').read().decode())"
done
pausa

titulo "Isolamento da persistência (Database per Service)"
echo "   mysql-pedidos (só a tabela pedidos):"
kubectl exec deploy/mysql-pedidos -- sh -c 'mysql -upedidos -p"$MYSQL_PASSWORD" pedidos -e "SHOW TABLES; SELECT id, status, valor_total_centavos FROM pedidos;" 2>/dev/null'
echo "   mysql-pagamento (só a tabela pagamentos):"
kubectl exec deploy/mysql-pagamento -- sh -c 'mysql -upagamento -p"$MYSQL_PASSWORD" pagamento -e "SHOW TABLES; SELECT pedido_id, status, valor_centavos FROM pagamentos;" 2>/dev/null'
echo "   mongo-catalogo (só a coleção produtos):"
kubectl exec deploy/mongo-catalogo -- mongosh catalogo --quiet --eval 'printjson(db.getCollectionNames()); printjson(db.produtos.countDocuments())'
echo "   mongo-notificacao (só a coleção notificacoes):"
kubectl exec deploy/mongo-notificacao -- mongosh notificacao --quiet --eval 'printjson(db.getCollectionNames()); printjson(db.notificacoes.countDocuments())'
pausa

titulo "RabbitMQ: exchange, filas e consumidores"
kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_exchanges name type durable | grep -E "name|ecommerce"
kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_queues name messages consumers
kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_bindings source_name destination_name routing_key | grep ecommerce
echo
echo "Painel: kubectl port-forward svc/rabbitmq 15672:15672  ->  http://localhost:15672 (ecommerce / ecommerce123)"
echo "Logs ao vivo: kubectl logs -f deploy/pedidos  |  deploy/pagamento  |  deploy/notificacao  |  -l app=catalogo --prefix"
