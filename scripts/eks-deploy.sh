#!/usr/bin/env bash
# Prepara o cluster EKS e implanta a aplicação. Passo a passo completo em AWS.md.
#
#   ./scripts/eks-deploy.sh ecommerce-n2 --so-infra   # fase 1: tags das subnets + Ingress Controller + Load Balancer
#                                                     #         (não precisa das imagens publicadas)
#   ./scripts/eks-deploy.sh ecommerce-n2              # fase 2: tudo acima + a aplicação inteira
#
# Pré-requisitos: cluster e node group criados pelo console, credenciais do Learner Lab
# em ~/.aws/credentials e, para a fase 2, as 4 imagens publicadas (scripts/build-push.sh).
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash no Windows: não converter argumentos que parecem caminho

SO_INFRA=0
POSICIONAIS=()
for arg in "$@"; do
  case "$arg" in
    --so-infra) SO_INFRA=1 ;;
    *) POSICIONAIS+=("$arg") ;;
  esac
done
CLUSTER="${POSICIONAIS[0]:-ecommerce-n2}"
REGIAO="${POSICIONAIS[1]:-us-east-1}"
INGRESS_NGINX_VERSAO="controller-v1.15.1"

cd "$(dirname "$0")/.."

if [ "$SO_INFRA" -eq 0 ] && grep -q "image: usuario-" k8s/*.yaml; then
  echo "!! ainda tem imagem com usuario-placeholder nos YAML:"
  grep -n "image: usuario-" k8s/*.yaml
  echo "!! rode scripts/build-push.sh para cada serviço (ou use --so-infra para preparar só a infraestrutura)"
  exit 1
fi

echo ">> credenciais"
aws sts get-caller-identity --query Arn --output text

echo ">> kubeconfig do cluster $CLUSTER ($REGIAO)"
aws eks update-kubeconfig --region "$REGIAO" --name "$CLUSTER"
if ! kubectl get nodes -o wide; then
  echo "!! o kubectl não conseguiu falar com o cluster."
  echo "   'Unauthorized' ou 'must be logged in': falta access entry para o seu usuário (AWS.md, problemas comuns)."
  echo "   'No resources found': o node group ainda não terminou de criar."
  exit 1
fi

# O controlador de Load Balancer que vem no EKS usa estas tags para escolher onde criar o NLB.
# Sem elas, o Service do Ingress pode ficar para sempre com EXTERNAL-IP <pending>.
echo ">> tags das subnets do cluster (para o Load Balancer)"
SUBNETS=$(aws eks describe-cluster --region "$REGIAO" --name "$CLUSTER" \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
echo "   subnets: $SUBNETS"
# shellcheck disable=SC2086
if aws ec2 create-tags --region "$REGIAO" --resources $SUBNETS \
     --tags "Key=kubernetes.io/role/elb,Value=1" "Key=kubernetes.io/cluster/$CLUSTER,Value=shared"; then
  echo "   tags aplicadas"
else
  echo "!! não consegui aplicar as tags. Faça pelo console (AWS.md, passo 5) e rode de novo."
fi

echo ">> NGINX Ingress Controller ($INGRESS_NGINX_VERSAO, provider AWS: cria um Network Load Balancer)"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSAO/deploy/static/provider/aws/deploy.yaml"
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=300s

esperar_lb() {
  echo ">> aguardando o hostname do Load Balancer (até 5 min)"
  LB=""
  for i in $(seq 1 30); do
    LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [ -n "$LB" ] && break
    sleep 10
  done
  if [ -z "$LB" ]; then
    echo "!! o Load Balancer não ganhou hostname. Veja o motivo com:"
    echo "   kubectl describe svc -n ingress-nginx ingress-nginx-controller   (seção Events)"
    echo "   Plano B: kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80"
    return 1
  fi
  echo "   hostname: $LB"
  echo ">> testando o Load Balancer (o DNS e os health checks do NLB levam de 1 a 3 min)"
  for i in $(seq 1 18); do
    cod=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$LB/" || true)
    if [ "$cod" = "404" ] || [ "$cod" = "200" ]; then
      echo "   Load Balancer respondendo (HTTP $cod vindo do NGINX)"
      return 0
    fi
    sleep 10
  done
  echo "!! o hostname existe mas ainda não responde. Espere mais alguns minutos e teste: curl -i http://$LB/"
}

if [ "$SO_INFRA" -eq 1 ]; then
  esperar_lb || true
  echo
  echo "Fase 1 pronta. Quando as 4 imagens estiverem publicadas: ./scripts/eks-deploy.sh $CLUSTER"
  exit 0
fi

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

esperar_lb || true

kubectl get pods -o wide
kubectl get ingress
echo
echo "URL externa: http://${LB:-<pendente>}"
echo "Próximo passo: ./scripts/preflight.sh"
