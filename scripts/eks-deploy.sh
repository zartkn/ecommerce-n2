#!/usr/bin/env bash
# Instala o NGINX Ingress Controller e aplica todos os manifests no cluster EKS.
# Pré-requisitos: cluster e node group já criados pelo console (ver README),
# credenciais do Learner Lab em ~/.aws/credentials e as 4 imagens já publicadas.
#
#   ./scripts/eks-deploy.sh [nome-do-cluster] [regiao]
set -euo pipefail

CLUSTER="${1:-ecommerce-n2}"
REGIAO="${2:-us-east-1}"
INGRESS_NGINX_VERSAO="controller-v1.15.1"

cd "$(dirname "$0")/.."

if grep -q "usuario-" k8s/*.yaml; then
  echo "!! ainda tem imagem com usuario-placeholder nos YAML:"
  grep -n "image: usuario-" k8s/*.yaml
  echo "!! rode scripts/build-push.sh para cada serviço antes do deploy"
  exit 1
fi

echo ">> kubeconfig do cluster $CLUSTER ($REGIAO)"
aws eks update-kubeconfig --region "$REGIAO" --name "$CLUSTER"
kubectl get nodes -o wide

echo ">> NGINX Ingress Controller ($INGRESS_NGINX_VERSAO, provider AWS: cria um Network Load Balancer)"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSAO/deploy/static/provider/aws/deploy.yaml"
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=300s

echo ">> infra e microsserviços"
kubectl apply -f k8s/00-secrets.yaml
kubectl apply -f k8s/01-rabbitmq.yaml
kubectl apply -f k8s/10-catalogo.yaml -f k8s/20-pedidos.yaml -f k8s/30-pagamento.yaml -f k8s/40-notificacao.yaml

# O webhook de validação do ingress-nginx às vezes demora alguns segundos para aceitar
echo ">> ingress"
for i in $(seq 1 12); do
  if kubectl apply -f k8s/90-ingress.yaml; then break; fi
  echo "   webhook ainda não está pronto, tentando de novo em 10 s ($i/12)"; sleep 10
done

echo ">> aguardando os Deployments"
for d in rabbitmq mongo-catalogo mongo-notificacao mysql-pedidos mysql-pagamento catalogo pedidos pagamento notificacao; do
  kubectl rollout status "deployment/$d" --timeout=300s
done

echo ">> aguardando o hostname do Load Balancer"
LB=""
for i in $(seq 1 30); do
  LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$LB" ] && break
  sleep 10
done

kubectl get pods -o wide
kubectl get ingress
echo
echo "URL externa: http://$LB"
echo "(o DNS do NLB pode levar de 1 a 3 minutos para responder)"
echo "Demo: ./scripts/demo.sh http://$LB"
