# E-commerce N2 · Cloud Native no Amazon EKS

Avaliação Somativa N2 de Back-End: Cloud Computing (PUCPR). Um e-commerce pequeno com 4 microsserviços independentes, cada um com seu banco, conversando por REST e RabbitMQ, implantado no Amazon EKS com NGINX Ingress Controller.

O contrato da integração (endpoints, eventos, erros, variáveis, seed) está no **[CONTRATOS.md](CONTRATOS.md)**. Ele é a fonte única da verdade: mudou algo, muda lá primeiro.

| Serviço | Responsável | Linguagem | Banco | Réplicas | Porta |
|---|---|---|---|---|---|
| [`ms-catalogo`](ms-catalogo) | Pedro | Node.js 20 (Express) | MongoDB 7 | **3** | 3000 |
| [`ms-pedidos`](ms-pedidos) | Edmund | Python 3.12 (FastAPI) | MySQL 8.4 | 1 | 8000 |
| [`ms-pagamento`](ms-pagamento) | Marco | C# .NET 8 (ASP.NET Core) | MySQL 8.4 | 1 | 8080 |
| [`ms-notificacao`](ms-notificacao) | Mickael | Python 3.12 (FastAPI) | MongoDB 7 | 1 | 8001 |

## Arquitetura

```
                          Cliente (curl / navegador)
                                     │
                       AWS Network Load Balancer
                                     │
                     NGINX Ingress Controller (EKS)
     ┌──────────────────┬────────────┴───────┬─────────────────────┐
 /api/produtos     /api/pedidos       /api/pagamentos     /api/notificacoes
     │                  │                    │                     │
 Service catalogo  Service pedidos    Service pagamento   Service notificacao
 3 Pods (Node)     1 Pod (Python)     1 Pod (C#)          1 Pod (Python)
     │                  │                    │                     │
 mongo-catalogo    mysql-pedidos      mysql-pagamento     mongo-notificacao

 pedidos ──REST (http://catalogo:3000)──> catalogo        valida produto e preço

 RabbitMQ · exchange "ecommerce.eventos" (topic)
   pedidos      publica  pedido.criado
   pagamento    consome  pedido.criado  → publica pagamento.aprovado | pagamento.recusado
   pedidos      consome  pagamento.*    → pedido vira PAGO | RECUSADO
   notificacao  consome  pagamento.*    → grava notificação + [EMAIL SIMULADO]
```

Regra do pagamento (mock): total até R$ 1.000,00 aprova, acima disso recusa com `LIMITE_EXCEDIDO`.

## Onde cada requisito está

| # | Requisito | Onde está |
|---|---|---|
| 1 | Um microsserviço por integrante | 4 pastas `ms-*`, cada uma com dono (tabela acima) |
| 2 | 2+ linguagens e 2+ bancos | Node.js, Python e C#; MongoDB e MySQL |
| 3 | Docker | `Dockerfile` em cada `ms-*` (o do C# é multi-stage) |
| 4 | EKS com Deployments, Pods e Services | `k8s/*.yaml` |
| 5 | Database per Service | 4 bancos separados, cada um com Deployment e Service próprios |
| 6 | REST entre serviços | `ms-pedidos/app/catalogo_client.py` chama o Catálogo |
| 7 | RabbitMQ | `messaging.py` (Python) e `Messaging/PedidoCriadoConsumer.cs` (C#) |
| 8 | Service Discovery | `CATALOGO_URL=http://catalogo:3000`, `DB_HOST=mysql-pedidos`, `RABBITMQ_HOST=rabbitmq` |
| 9 | Escalabilidade horizontal | `replicas: 3` em `k8s/10-catalogo.yaml` + `GET /api/produtos/instance` + header `X-Pod-Name` |
| 10 | Ingress | `k8s/90-ingress.yaml` com 4 regras de path |

## Estrutura

```
ecommerce-n2/
├── CONTRATOS.md            contrato da integração (leitura obrigatória)
├── docker-compose.yml      ambiente local completo + gateway NGINX imitando o Ingress
├── local/nginx.conf        regras do gateway local (iguais às do Ingress)
├── ms-catalogo/            Pedro   · Node.js + MongoDB
├── ms-pedidos/             Edmund  · Python + MySQL
├── ms-pagamento/           Marco   · C# + MySQL
├── ms-notificacao/         Mickael · Python + MongoDB
├── k8s/
│   ├── 00-secrets.yaml     senhas (Secret ecommerce-secrets)
│   ├── 01-rabbitmq.yaml
│   ├── 10-catalogo.yaml    mongo-catalogo + catalogo (3 réplicas)
│   ├── 20-pedidos.yaml     mysql-pedidos + pedidos
│   ├── 30-pagamento.yaml   mysql-pagamento + pagamento
│   ├── 40-notificacao.yaml mongo-notificacao + notificacao
│   └── 90-ingress.yaml     regras do NGINX Ingress
└── scripts/
    ├── build-push.sh       builda (linux/amd64), publica no Docker Hub e atualiza o YAML
    ├── eks-deploy.sh       instala o Ingress Controller e aplica tudo no EKS
    ├── demo.sh             roteiro da demo pelas APIs
    └── evidencias-k8s.sh   evidências de cluster, discovery, isolamento e RabbitMQ
```

## 1. Rodar local (desenvolvimento)

Precisa só do Docker Desktop.

```bash
docker compose up --build
```

Na primeira vez, alguns serviços podem reiniciar uma ou duas vezes enquanto os bancos sobem. Isso é esperado: cada serviço tenta conectar a cada 5 s por até 2 minutos.

Depois que tudo subir:

```bash
./scripts/demo.sh                     # mesmo roteiro da apresentação, em http://localhost
```

- Painel do RabbitMQ: http://localhost:15672 (`ecommerce` / `ecommerce123`)
- Swagger: http://localhost/api/pedidos/docs, http://localhost/api/notificacoes/docs, http://localhost/api/pagamentos/swagger
- Cada serviço também responde direto na própria porta (3000, 8000, 8080, 8001)

Para subir só parte do sistema enquanto o resto não está pronto:

```bash
docker compose up --build rabbitmq mongo-catalogo catalogo     # só o Catálogo
```

Dá para simular um serviço que ainda não existe publicando uma mensagem à mão no painel do RabbitMQ: **Exchanges → ecommerce.eventos → Publish message**, com a routing key e o JSON do envelope da seção 7 do contrato.

## 2. Publicar as imagens

Cada integrante publica a imagem do próprio serviço na própria conta do Docker Hub (repositório público):

```bash
docker login
./scripts/build-push.sh catalogo    <seu-usuario>     # Pedro
./scripts/build-push.sh pedidos     <seu-usuario>     # Edmund
./scripts/build-push.sh pagamento   <seu-usuario>     # Marco
./scripts/build-push.sh notificacao <seu-usuario>     # Mickael
```

O script builda em `linux/amd64` (arquitetura dos nós do EKS), faz o push e troca o `image:` no YAML do serviço. Faça commit do YAML alterado. Mudou o código? Sobe a tag: `./scripts/build-push.sh pedidos <usuario> 1.0.1`.

## 3. Criar o cluster no AWS Academy Learner Lab

No Learner Lab o IAM é bem limitado: não dá para criar roles, então tudo usa a **LabRole**. Por isso o cluster é criado pelo console, e não pelo `eksctl` (ele tenta criar roles e falha).

**3.1 Credenciais (toda vez que abrir o lab)**
1. Start Lab, esperar a bolinha ficar verde.
2. **AWS Details → AWS CLI: Show** e copiar o bloco inteiro para `~/.aws/credentials` (no Windows: `C:\Users\<voce>\.aws\credentials`).
3. Região: `us-east-1`.
4. Testar: `aws sts get-caller-identity`

As credenciais expiram quando a sessão acaba. Sessão nova, credenciais novas.

**3.2 Cluster** (EKS → Clusters → Create cluster)
- Configuração: **Custom configuration** (desligar o EKS Auto Mode)
- Nome: `ecommerce-n2`
- Cluster IAM role: **LabRole**
- Versão do Kubernetes: a padrão
- Autenticação: EKS API and ConfigMap
- Rede: VPC padrão, subnets de pelo menos 2 zonas, **sem `us-east-1e`** (o EKS não aceita essa zona)
- Endpoint: Public
- Add-ons: os padrões (CoreDNS, kube-proxy, Amazon VPC CNI)
- Criar e esperar ficar **Active** (10 a 15 minutos)

**3.3 Node group** (cluster → Compute → Add node group)
- Nome: `ng-ecommerce`
- Node IAM role: **LabRole**
- AMI: Amazon Linux 2023 (x86_64)
- Instância: `t3.medium`, disco 20 GB
- Escala: desejado 2, mínimo 2, máximo 3
- Subnets: as mesmas do cluster
- Criar e esperar ficar **Active** (5 minutos)

**3.4 Deploy**

```bash
aws eks update-kubeconfig --region us-east-1 --name ecommerce-n2
kubectl get nodes                       # 2 nós Ready
./scripts/eks-deploy.sh ecommerce-n2    # Ingress Controller + todos os manifests
```

O script termina mostrando a URL externa (hostname do Load Balancer). O DNS do NLB pode levar de 1 a 3 minutos para responder.

**3.5 Depois da apresentação**: apagar o node group e depois o cluster. O control plane do EKS cobra por hora mesmo sem uso e consome o crédito do lab.

## 4. Roteiro da apresentação

> **O roteiro oficial de 5 minutos, com falas, checklist do dia e perguntas prováveis, está no [APRESENTACAO.md](APRESENTACAO.md).** Os scripts são `scripts/preflight.sh`, `scripts/apresentacao.sh` e `scripts/logs-fluxo.sh`. A tabela abaixo é a versão longa, para ensaio e para estudar.

Dois terminais lado a lado e o painel do RabbitMQ aberto (`kubectl port-forward svc/rabbitmq 15672:15672`).

| Etapa | Comando | Rubrica |
|---|---|---|
| Arquitetura, linguagens, bancos e donos | slide com o diagrama acima | R1 |
| Cluster, Deployments, Pods (3 do catálogo) e Services | `./scripts/evidencias-k8s.sh` (blocos 1 e 2) | R2 |
| Ingress e Load Balancer | `./scripts/evidencias-k8s.sh` (bloco 3) | R2 |
| Service Discovery | `./scripts/evidencias-k8s.sh` (bloco 4) | R2 |
| Isolamento dos bancos | `./scripts/evidencias-k8s.sh` (bloco 5) | R1 |
| Balanceamento entre réplicas | `./scripts/demo.sh http://<LB>` (etapa 1) | R2 |
| Fluxo REST + RabbitMQ aprovado | `./scripts/demo.sh` (etapa 3) + painel do RabbitMQ + `kubectl logs -f deploy/pagamento` | R3 |
| Fluxo recusado | `./scripts/demo.sh` (etapas 4 e 5) | R3 |
| Idempotência | republicar pelo painel o mesmo `pagamento.aprovado`: pedido continua PAGO e o Notificação loga `duplicada ignorada` | R3 |
| Cada integrante mostra o próprio código | README de cada `ms-*` | R1 |

Logs que valem mostrar ao vivo:

```bash
kubectl logs -f deploy/pedidos
kubectl logs -f deploy/pagamento
kubectl logs -f deploy/notificacao
kubectl logs -l app=catalogo --prefix -f      # as 3 réplicas juntas, com o nome do Pod
```

**Plano B:** gravar um vídeo do ensaio completo no EKS na véspera. Se o Learner Lab der problema na hora, a evidência existe.

## 5. Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `ImagePullBackOff` | nome da imagem errado ou repositório privado | conferir o `image:` no YAML e deixar o repo público no Docker Hub |
| `exec format error` no log | imagem buildada em arm64 (Mac M1/M2/M3) | usar `scripts/build-push.sh`, que força `linux/amd64` |
| Pod reinicia 1 ou 2 vezes na subida | banco ou RabbitMQ ainda subindo | normal; se passar de 3, ver `kubectl logs <pod> --previous` |
| Primeiro POST devolve 503 `MENSAGERIA_INDISPONIVEL` | o Pagamento ainda não subiu e a fila dele não existe | esperar o Pod do pagamento ficar Ready e tentar de novo |
| `failed calling webhook ... ingress-nginx` | controller ainda iniciando | o `eks-deploy.sh` já tenta de novo; se rodar à mão, espere 30 s |
| URL do Load Balancer não responde | DNS do NLB propagando | esperar 1 a 3 minutos |
| Pods em `Pending` | falta de recurso nos nós | subir o node group para 3 nós |
| `kubectl` pede credencial ou dá `Unauthorized` | sessão do lab expirou | copiar o AWS Details de novo e rodar `update-kubeconfig` |
| Dados sumiram depois de reabrir o lab | bancos sem volume persistente (escolha consciente, ver contrato 10.1) | o seed recria os produtos; pedidos são recriados na demo |

## Decisões de projeto (para explicar na banca)

- **Bancos sem volume persistente**: o driver EBS CSI precisa de permissões de IAM que o Learner Lab não dá. Em produção seria PVC com EBS ou um RDS.
- **Dinheiro em centavos inteiros**: evita erro de arredondamento entre Node, Python e C#.
- **Exchange topic com uma fila por consumidor**: Pedidos e Notificação recebem cada um a sua cópia de `pagamento.*`. Com fila única, as mensagens seriam divididas entre eles.
- **Ack manual depois de gravar**: se o serviço cair no meio, a mensagem não se perde.
- **Idempotência nos 3 consumidores**: `pedido_id` único no Pagamento, update só se `PENDENTE` no Pedidos, índice único `pedidoId + tipo` no Notificação.
- **Commit antes de publicar** no Pedidos, com `mandatory` e confirmação do broker: nenhum pedido fica `PENDENTE` para sempre.
- **Sem keep-alive na chamada do Pedidos para o Catálogo**: cada chamada abre conexão nova e o kube-proxy distribui entre as 3 réplicas, o que aparece no log `catalogo consultado ... pod=`.
