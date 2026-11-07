# Passo a passo na AWS (AWS Academy Learner Lab)

Do zero até a aplicação rodando no EKS e pronta para terça. Tempo total: de 45 a 60 minutos, a maior parte esperando a AWS criar as coisas.

Quem fizer este passo a passo vira o **dono do cluster**: o cluster fica na conta do Learner Lab dessa pessoa, e a apresentação precisa sair dessa conta.

| Fase | O quê | Tempo |
|---|---|---|
| 0 | Preparar o computador | 10 min (uma vez só) |
| 1 | Abrir o lab e configurar as credenciais | 5 min |
| 2 | Criar o cluster EKS | 15 min |
| 3 | Criar o node group | 5 min |
| 4 | Conectar o kubectl | 2 min |
| 5 | Infra do Kubernetes: tags, Ingress e Load Balancer | 5 min |
| 6 | Publicar as 4 imagens | 15 min |
| 7 | Implantar a aplicação e checar | 10 min |
| 8 | Manter pronto até terça | |
| 9 | Desmontar depois da apresentação | 10 min |

A fase 5 não depende das imagens. Dá para fazer as fases 1 a 5 agora e as fases 6 e 7 assim que as imagens existirem.

---

## Fase 0 · Preparar o computador

No Windows, abra o PowerShell **como administrador** e instale:

```powershell
winget install Git.Git Amazon.AWSCLI Kubernetes.kubectl jqlang.jq
```

Feche e abra de novo o terminal. A partir daqui, **tudo roda no Git Bash** (menu Iniciar → Git Bash). Os scripts são bash e não funcionam no PowerShell.

```bash
aws --version && kubectl version --client && jq --version
cd ~/Documents/PROJETOS/ecommerce-n2   # ou onde estiver o repositório
git pull
```

Docker Desktop só é necessário na fase 6, para quem for publicar imagem.

---

## Fase 1 · Abrir o lab e configurar as credenciais

1. Entre no AWS Academy → Learner Lab → **Start Lab**. Espere a bolinha ao lado de "AWS" ficar **verde**.
2. Anote o crédito restante, que aparece no topo da página (por exemplo "Used $3.2 of $100").
3. Clique em **AWS Details** → **AWS CLI: Show** e copie o bloco inteiro, que começa com `[default]`.
4. No Git Bash, cole o bloco no arquivo de credenciais:

```bash
mkdir -p ~/.aws
notepad ~/.aws/credentials       # cole o bloco, salve e feche
aws configure set region us-east-1
aws sts get-caller-identity
```

O último comando tem que mostrar algo como `arn:aws:sts::123456789012:assumed-role/voclabs/...`. **Anote o número da conta** (os 12 dígitos), porque a fase 4 pode precisar dele.

> As credenciais duram só a sessão do lab (umas 4 horas). Abriu o lab de novo, cole o AWS Details de novo nesse mesmo arquivo. O resto continua funcionando.

Clique em **AWS** (o link com a bolinha verde) para abrir o console. Confira no canto superior direito se a região é **N. Virginia (us-east-1)**.

---

## Fase 2 · Criar o cluster EKS

Console → busque **EKS** → **Clusters** → **Create cluster**.

**Tela "Configure cluster"**

| Campo | Valor |
|---|---|
| Configuration options | **Custom configuration** |
| Use EKS Auto Mode | **desligado** (o Auto Mode precisa de roles que o Learner Lab não deixa criar) |
| Name | `ecommerce-n2` |
| Cluster IAM role | **LabRole** |
| Kubernetes version | **1.35**. Não use a mais nova: o NGINX Ingress Controller foi descontinuado e só é testado até a 1.35 |
| Upgrade policy | **Standard**. Nunca Extended, que cobra 6 vezes mais por hora |
| Bootstrap cluster administrator access | **Allow** |
| Cluster authentication mode | **EKS API and ConfigMap** |
| Secrets encryption, ARC zonal shift | desligados |

Next.

**Tela "Specify networking"**

| Campo | Valor |
|---|---|
| VPC | a VPC padrão (default) |
| Subnets | todas, **menos a de `us-east-1e`**. O EKS não aceita essa zona e o cluster falha |
| Security groups | o `default` |
| IP address family | IPv4 |
| Cluster endpoint access | **Public** |

Para saber qual subnet é a da `us-east-1e`, passe o mouse ou abra a lista: a zona aparece ao lado de cada subnet.

Next.

**Tela "Configure observability"**: deixe tudo desligado. Next.

**Tela "Select add-ons"**: deixe marcados só **CoreDNS**, **kube-proxy**, **Amazon VPC CNI** e **Amazon EKS Pod Identity Agent**. Se vier outro add-on marcado, desmarque. Next, e Next de novo na tela de versões dos add-ons.

**Revise e clique em Create.** O status fica **Creating** por 10 a 15 minutos. Espere ficar **Active**.

| Erro | O que fazer |
|---|---|
| "Cannot create cluster ... us-east-1e" ou falta de capacidade | volte e desmarque a subnet da `us-east-1e` |
| Erro sobre service-linked role | clique em Create de novo. Na primeira vez a AWS às vezes ainda está criando essa role |
| LabRole não aparece na lista | atualize a página. Se continuar, confira se o lab está verde |

---

## Fase 3 · Criar o node group

Com o cluster **Active**: abra o cluster → aba **Compute** → **Add node group**.

**Tela "Configure node group"**

| Campo | Valor |
|---|---|
| Name | `ng-ecommerce` |
| Node IAM role | **LabRole** |

Next.

**Tela "Set compute and scaling configuration"**

| Campo | Valor |
|---|---|
| AMI type | **Amazon Linux 2023 (x86_64) Standard** |
| Capacity type | On-Demand |
| Instance types | **só `t3.medium`** (remova qualquer outro da lista) |
| Disk size | 20 GiB |
| Desired / Minimum / Maximum | **2 / 2 / 3** |
| Maximum unavailable | 1 node |

Next.

**Tela "Specify networking"**: as subnets já vêm preenchidas com as do cluster. Deixe assim. **Configure remote access** desligado. Next → **Create**.

Espere de 3 a 5 minutos até o status ficar **Active**.

---

## Fase 4 · Conectar o kubectl

No Git Bash:

```bash
aws eks update-kubeconfig --region us-east-1 --name ecommerce-n2
kubectl get nodes
```

Tem que aparecer **2 nós com STATUS Ready**.

**Se der `Unauthorized` ou `You must be logged in to the server`**, falta dar acesso ao seu usuário dentro do cluster:

1. Console → EKS → `ecommerce-n2` → aba **Access** → **Create access entry**
2. IAM principal ARN: `arn:aws:iam::<NUMERO-DA-CONTA>:role/voclabs` (o número anotado na fase 1)
3. Type: Standard → Next
4. Policy name: **AmazonEKSClusterAdminPolicy**, Access scope: **Cluster** → **Add policy** → Next → **Create**
5. Rode `kubectl get nodes` de novo

---

## Fase 5 · Infra do Kubernetes: tags, Ingress e Load Balancer

Esta é a parte com mais chance de esbarrar em permissão do Learner Lab, então vale fazer agora, mesmo sem as imagens:

```bash
./scripts/eks-deploy.sh ecommerce-n2 --so-infra
```

O script:
1. confere as credenciais e o kubectl;
2. coloca nas subnets do cluster as tags `kubernetes.io/role/elb=1` e `kubernetes.io/cluster/ecommerce-n2=shared`. É por elas que o EKS escolhe onde criar o Load Balancer;
3. instala o NGINX Ingress Controller, que cria um Network Load Balancer na AWS;
4. espera o Load Balancer ganhar um endereço e testa se ele responde.

**Resultado esperado:**

```
   hostname: a1b2c3...elb.us-east-1.amazonaws.com
   Load Balancer respondendo (HTTP 404 vindo do NGINX)
Fase 1 pronta.
```

O 404 é o resultado certo: o NGINX respondeu, só não existe nenhuma rota ainda.

**Se o script avisar que não conseguiu aplicar as tags**, aplique pelo console e rode o script de novo:
Console → **VPC** → **Subnets** → para cada subnet do cluster (todas menos a da `us-east-1e`): selecione → aba **Tags** → **Manage tags** → adicione as duas tags:

| Key | Value |
|---|---|
| `kubernetes.io/role/elb` | `1` |
| `kubernetes.io/cluster/ecommerce-n2` | `shared` |

**Se o Load Balancer não ganhar hostname**, veja o motivo com:

```bash
kubectl describe svc -n ingress-nginx ingress-nginx-controller
```

A seção **Events**, no final, diz o que falhou. Me manda essa saída. Enquanto isso, o plano B continua de pé: `kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80`, que mantém a demonstração passando pelo Ingress.

---

## Fase 6 · Publicar as 4 imagens

O ideal é cada um publicar a imagem do próprio serviço, com a própria conta do Docker Hub. Se alguém ainda não fez, o dono do cluster pode publicar as que faltarem com a conta dele para não travar o grupo. A autoria do código continua sendo de cada um.

Com o **Docker Desktop aberto**, no Git Bash:

```bash
docker login
./scripts/build-push.sh catalogo    <usuario-dockerhub>
./scripts/build-push.sh pedidos     <usuario-dockerhub>
./scripts/build-push.sh pagamento   <usuario-dockerhub>
./scripts/build-push.sh notificacao <usuario-dockerhub>
grep -n "image: " k8s/*.yaml        # nenhuma linha pode ter usuario-
git add k8s/ && git commit -m "Imagens publicadas no Docker Hub" && git push
```

Depois confira em hub.docker.com → Repositories se os 4 repositórios estão **Public**. Imagem privada dá `ImagePullBackOff` no cluster.

> O `pagamento` é o único que ainda não foi buildado de verdade. Se o build dele falhar, me manda a saída completa.

---

## Fase 7 · Implantar a aplicação e checar

```bash
git pull
./scripts/eks-deploy.sh ecommerce-n2
./scripts/preflight.sh
```

O `eks-deploy.sh` aplica tudo e espera os 9 Deployments ficarem prontos (uns 3 minutos, por causa dos bancos). O `preflight.sh` tem que terminar com **TUDO PRONTO: 22 checagens OK**.

Depois, um ensaio completo:

```bash
./scripts/apresentacao.sh
```

Se algum Pod não subir:

```bash
kubectl get pods                         # qual está com problema
kubectl describe pod <nome-do-pod>       # Events no final: por que não subiu
kubectl logs <nome-do-pod> --previous    # log da última vez que ele caiu
```

---

## Fase 8 · Manter pronto até terça

- **Não apague nada.** Quando a sessão do lab acaba, a AWS para os nós, mas o cluster, o Load Balancer e os manifests continuam lá.
- **Para voltar a usar:** Start Lab → cole o AWS Details em `~/.aws/credentials` → `./scripts/preflight.sh`. Os nós levam alguns minutos para voltar. Se continuarem NotReady depois de 10 minutos: Console → **EC2** → **Instances** → selecione as instâncias paradas → **Instance state** → **Start instance**.
- **Conserto universal** se o preflight falhar depois de reabrir o lab: `kubectl rollout restart deployment catalogo pedidos pagamento notificacao` e, depois de 2 minutos, `./scripts/preflight.sh` de novo.
- **Mudou o código de um serviço:** `./scripts/build-push.sh <servico> <usuario> 1.0.1`, depois `kubectl apply -f k8s/<arquivo-do-servico>.yaml` e `kubectl rollout status deployment/<servico>`.
- **Custo aproximado em us-east-1:** uns US$ 0,21 por hora com o lab aberto (control plane, 2 nós t3.medium e o Load Balancer) e uns US$ 0,12 por hora com o lab fechado (os nós param, o resto continua cobrando). De sábado a terça dá entre US$ 10 e US$ 15. Confira se o crédito anotado na fase 1 cobre isso.

---

## Fase 9 · Desmontar depois da apresentação

Nesta ordem. Se o cluster for apagado primeiro, o Load Balancer fica órfão e continua cobrando:

```bash
kubectl delete -f k8s/90-ingress.yaml
kubectl delete namespace ingress-nginx     # apaga o Load Balancer da AWS; espere 2 min
```

Depois, no console:
1. EKS → `ecommerce-n2` → aba **Compute** → `ng-ecommerce` → **Delete**. Espere sumir (uns 5 min).
2. EKS → `ecommerce-n2` → **Delete cluster**.
3. EC2 → **Load Balancers**: confira se não sobrou nenhum. Se sobrou, apague.

---

## Problemas comuns

| Sintoma | Causa | O que fazer |
|---|---|---|
| Cluster falha ao criar citando `us-east-1e` | zona não suportada pelo EKS | criar de novo sem a subnet da `us-east-1e` |
| `kubectl`: `Unauthorized` | seu usuário não tem acesso dentro do cluster | access entry da fase 4 |
| `kubectl`: erro de credencial ou token expirado | a sessão do lab acabou | colar o AWS Details de novo |
| `EXTERNAL-IP <pending>` no Service do Ingress | subnets sem as tags | tags da fase 5 e `kubectl describe svc -n ingress-nginx ingress-nginx-controller` |
| Load Balancer tem hostname mas não responde | DNS e health checks do NLB ainda subindo | esperar de 2 a 3 min |
| Pod em `ImagePullBackOff` | nome da imagem errado ou repositório privado | conferir o `image:` no YAML e deixar o repositório Public |
| Pod em `CrashLoopBackOff` com `exec format error` | imagem buildada em arm64 (Mac com chip Apple) | publicar de novo com `scripts/build-push.sh`, que força amd64 |
| Pod em `Pending` com `Too many pods` ou `Insufficient memory` | nós cheios | EKS → Compute → `ng-ecommerce` → **Edit** → Desired 3 |
| Nós `NotReady` depois de reabrir o lab | instâncias voltando | esperar 10 min; se não voltar, EC2 → Start instance |
| Primeiro POST devolve 503 `MENSAGERIA_INDISPONIVEL` | o Pagamento ainda não criou a fila dele | esperar o Pod do pagamento ficar Ready |
