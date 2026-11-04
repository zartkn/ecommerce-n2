#!/usr/bin/env bash
# Builda a imagem de UM microsserviço, publica no Docker Hub e atualiza o YAML do k8s.
# Cada integrante roda para o próprio serviço, com a própria conta do Docker Hub.
#
#   docker login
#   ./scripts/build-push.sh catalogo    <usuario-dockerhub> [tag]   # Pedro
#   ./scripts/build-push.sh pedidos     <usuario-dockerhub> [tag]   # Edmund
#   ./scripts/build-push.sh pagamento   <usuario-dockerhub> [tag]   # Marco
#   ./scripts/build-push.sh notificacao <usuario-dockerhub> [tag]   # Mickael
#
# A imagem sai sempre em linux/amd64, que é a arquitetura dos nós t3.medium do EKS.
# Sem isso, quem builda num Mac M1/M2/M3 gera imagem arm64 e o Pod dá "exec format error".
set -euo pipefail

SERVICO="${1:-}"
USUARIO="${2:-}"
TAG="${3:-1.0.0}"

case "$SERVICO" in
  catalogo)    YAML="k8s/10-catalogo.yaml" ;;
  pedidos)     YAML="k8s/20-pedidos.yaml" ;;
  pagamento)   YAML="k8s/30-pagamento.yaml" ;;
  notificacao) YAML="k8s/40-notificacao.yaml" ;;
  *) echo "uso: $0 <catalogo|pedidos|pagamento|notificacao> <usuario-dockerhub> [tag]"; exit 1 ;;
esac
[ -n "$USUARIO" ] || { echo "informe o usuario do Docker Hub"; exit 1; }

cd "$(dirname "$0")/.."
IMAGEM="$USUARIO/ms-$SERVICO:$TAG"

echo ">> build + push $IMAGEM (linux/amd64)"
docker buildx build --platform linux/amd64 -t "$IMAGEM" --push "ms-$SERVICO"

echo ">> atualizando $YAML"
sed -i.bak -E "s#image: [^ ]+/ms-$SERVICO:[^ ]+#image: $IMAGEM#" "$YAML" && rm -f "$YAML.bak"
grep -n "image: .*ms-$SERVICO" "$YAML"

echo ">> pronto. Faça commit do $YAML para o grupo usar a imagem nova."
