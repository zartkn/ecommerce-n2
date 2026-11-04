# Apresentação · 10/11 · 5 minutos no EKS

Sem slides. O professor quer ver funcionando e avalia assim:

| Critério | Peso | Tempo no roteiro |
|---|---|---|
| Implantação no EKS e escalabilidade horizontal | **40%** | ~2 min (blocos 1 e 2) |
| Microsserviços e diversidade tecnológica | 30% | ~1 min (abertura e bloco 3) |
| Integração REST e mensageria RabbitMQ | 30% | ~1min30 (bloco 4) |

A regra de ouro: **a gente não explica, a gente mostra.** Cada fala tem no máximo duas frases e é dita enquanto o comando roda.

## 1. Montagem do palco

Tudo no notebook do **Pedro** (o cluster está na conta dele), conectado ao projetor:

| Janela | O que fica aberto |
|---|---|
| Terminal A (metade esquerda) | `./scripts/apresentacao.sh` |
| Terminal B (metade direita) | `./scripts/logs-fluxo.sh` (logs ao vivo de todos os serviços, com o nome do Pod) |
| Terminal C (minimizado) | `kubectl port-forward svc/rabbitmq 15672:15672` |
| Navegador, aba 1 | http://localhost:15672 → aba **Queues** (login `ecommerce` / `ecommerce123`) |
| Navegador, aba 2 | repositório no GitHub, se o professor quiser ver código |

- Fonte do terminal em 18 ou mais, tema escuro, janelas lado a lado
- Usar Git Bash ou WSL (os scripts são bash)
- Celular com hotspot ligado como internet reserva

## 2. Roteiro cronometrado

O Pedro digita tudo. Cada um fala na sua vez. Uma tecla Enter separa um bloco do outro.

| Tempo | Quem fala | Tela | Fala (curta, com as próprias palavras) |
|---|---|---|---|
| 0:00 | **Edmund** | Terminal A limpo | "Nosso projeto é um e-commerce com 4 microsserviços, em 3 linguagens e 2 bancos, rodando agora no EKS. Vamos mostrar tudo ao vivo." |
| 0:15 | **Pedro** | Bloco 1 | "Esse é o nosso cluster EKS com 2 nós. Aqui estão os Deployments, os Pods e os Services. Cada microsserviço tem seu banco. A entrada é pelo NGINX Ingress Controller, atrás de um Load Balancer da AWS." |
| 1:00 | **Pedro** | Bloco 2 | "O Catálogo tem 3 réplicas. Fazendo 9 chamadas pelo Ingress, cada Pod respondeu 3. Agora vou escalar para 5 ao vivo... As réplicas novas já entram no balanceamento. E volto para 3." |
| 2:30 | **Os 4**, um de cada vez | Bloco 3 | Pedro: "Catálogo em Node.js com MongoDB." Edmund: "Pedidos em Python com MySQL." Marco: "Pagamento em C# .NET com MySQL próprio." Mickael: "Notificação em Python com MongoDB próprio." |
| 3:10 | **Edmund** | Bloco 4, primeira parte | "Vou criar um pedido. O Pedidos consulta o Catálogo por REST, usando o nome do Service, grava como PENDENTE e publica `pedido.criado` no RabbitMQ." |
| 3:30 | **Marco** | Terminal B (logs) | "O Pagamento consumiu a mensagem da fila dele, aprovou, gravou no MySQL dele e publicou `pagamento.aprovado`." |
| 3:45 | **Mickael** | Terminal B + aba Queues | "O Notificação consumiu da fila dele e mandou o e-mail simulado. No painel dá para ver as 3 filas, cada uma com seu consumidor." |
| 4:00 | **Edmund** | Bloco 4, segunda parte | "O pedido já está PAGO. E um pedido acima de R$ 1.000 é recusado pelo mesmo fluxo." |
| 4:30 | **Edmund** | | "É isso. Estamos à disposição para perguntas." |

Sobrou mais de 30 segundos no ensaio? Rodar `./scripts/apresentacao.sh fila` no final (Marco narra): o Pagamento sai do ar, o pedido entra, a mensagem fica esperando na fila e é processada quando o serviço volta. É a prova mais forte de comunicação assíncrona.

## 3. Se o professor pedir algo a mais

| Pedido | Comando | Quem responde |
|---|---|---|
| "Mostra a mensagem esperando na fila" | `./scripts/apresentacao.sh fila` | Marco |
| "E se um Pod morrer?" | `./scripts/apresentacao.sh healing` | Pedro |
| "Como um serviço acha o outro?" | `./scripts/apresentacao.sh discovery` | Edmund |
| "Os bancos são separados mesmo?" | `./scripts/apresentacao.sh bancos` | Mickael |
| "Como está o RabbitMQ por dentro?" | `./scripts/apresentacao.sh rabbit` | Marco ou Mickael |
| "Repete só a escalabilidade" | `./scripts/apresentacao.sh 2` | Pedro |

## 4. Checklist

### Até segunda 09
- [ ] Deploy feito e `./scripts/preflight.sh` com **TUDO PRONTO**
- [ ] 3 ensaios cronometrados com o roteiro acima. Meta: terminar em 4min30
- [ ] **Gravar um ensaio completo em vídeo** (plano C)
- [ ] Notebook do Pedro com Git Bash (ou WSL), kubectl, AWS CLI e o repo atualizado
- [ ] Um segundo notebook (Edmund) com kubectl e AWS CLI instalados, como reserva
- [ ] **Não apagar o cluster depois do ensaio**

### Terça 10
- [ ] **T-60 min:** Pedro abre o Learner Lab (Start Lab) e espera ficar verde
- [ ] **T-45:** copia o AWS Details para `~/.aws/credentials`, roda `aws eks update-kubeconfig --region us-east-1 --name ecommerce-n2`
- [ ] **T-40:** `./scripts/preflight.sh`. Se os nós ainda estiverem NotReady, esperar 5 min e rodar de novo. Se continuar, EC2 → Instances → Start nas instâncias paradas
- [ ] **T-15:** abrir os terminais B e C e o painel do RabbitMQ na aba Queues
- [ ] **T-5:** `./scripts/preflight.sh` de novo, fechar notificações do sistema, `clear` no terminal A
- [ ] Pedro manda o texto do AWS Details para o Edmund no privado (reserva, caso o notebook dele falhe)
- [ ] **Depois da apresentação:** apagar o node group e depois o cluster

## 5. Planos B e C

| Problema | O que fazer |
|---|---|
| Load Balancer sem hostname ou sem responder | `kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80` e `BASE=http://localhost:8080 ./scripts/apresentacao.sh`. Continua passando pelo Ingress |
| Script travar | usar os comandos avulsos da seção 6 |
| Notebook do Pedro falhar | Edmund usa as credenciais que o Pedro mandou e roda do notebook dele |
| Cluster fora do ar | mostrar o vídeo do ensaio e explicar o que aconteceu |

## 6. Comandos avulsos (cola)

```bash
# EKS
kubectl get nodes
kubectl get deployments
kubectl get pods -o wide
kubectl get services
kubectl get ingress

# Escalabilidade
kubectl get deployment catalogo
kubectl scale deployment catalogo --replicas=5
kubectl get pods -l app=catalogo -o wide
for i in $(seq 1 10); do curl -s http://<LB>/api/produtos/instance; echo; done
kubectl scale deployment catalogo --replicas=3

# Diversidade
kubectl get deployments -o custom-columns='NOME:.metadata.name,IMAGEM:.spec.template.spec.containers[0].image'
kubectl exec deploy/catalogo -- node --version
kubectl exec deploy/pedidos -- python --version
kubectl exec deploy/pagamento -- dotnet --list-runtimes

# REST + RabbitMQ
curl -s -X POST http://<LB>/api/pedidos -H 'Content-Type: application/json' \
  -d '{"produtoId":"prod-001","quantidade":2,"emailCliente":"cliente@email.com"}'
curl -s http://<LB>/api/pedidos/<id>
curl -s http://<LB>/api/pagamentos/pedido/<id>
curl -s "http://<LB>/api/notificacoes?pedidoId=<id>"
kubectl exec deploy/rabbitmq -- rabbitmqctl -q list_queues name consumers messages
kubectl logs deploy/pagamento --tail=10
kubectl logs deploy/notificacao --tail=10
```

## 7. Perguntas prováveis (cada um estuda as do próprio serviço)

**Pedro (cluster e Catálogo)**
- *O que o `kubectl scale` faz por baixo?* Muda o número de réplicas do Deployment; o ReplicaSet cria ou remove Pods até bater com o desejado.
- *Como as requisições são divididas entre as réplicas?* O Ingress NGINX conhece os endpoints do Service e distribui entre os Pods. Dentro do cluster, o kube-proxy faz o mesmo para quem chama pelo nome do Service.
- *Por que os Services são ClusterIP e não LoadBalancer?* Só o Ingress Controller fica exposto. Os serviços ficam acessíveis só dentro do cluster.
- *Por que o seed usa upsert?* As 3 réplicas sobem juntas e todas rodam o seed; com upsert por `_id` ninguém duplica produto.

**Edmund (Pedidos)**
- *Como o Pedidos encontra o Catálogo?* Pela variável `CATALOGO_URL=http://catalogo:3000`. O CoreDNS resolve `catalogo` para o IP do Service, nunca para o IP de um Pod.
- *Por que grava antes de publicar?* Se publicasse antes, o Pagamento poderia responder antes de o pedido existir no banco, e ele ficaria PENDENTE para sempre.
- *E se o RabbitMQ estiver fora?* O POST devolve 503 e o pedido é desfeito.

**Marco (Pagamento)**
- *Por que ack manual?* Só confirma a mensagem depois de gravar e publicar. Se cair no meio, a mensagem não se perde.
- *E se a mesma mensagem chegar duas vezes?* Existe índice único em `pedido_id`; a segunda é ignorada.
- *O que acontece se o Pagamento cair?* As mensagens ficam guardadas na fila durável e são processadas quando ele volta (extra `fila`).

**Mickael (Notificação)**
- *Por que uma fila só do Notificação?* Com o exchange topic, cada fila ligada em `pagamento.*` recebe sua própria cópia. Com uma fila só para Pedidos e Notificação, um roubaria a mensagem do outro.
- *Como evita e-mail duplicado?* Índice único em `pedidoId + tipo` no Mongo; duplicado é ignorado com log de aviso.
- *Por que os bancos não têm volume persistente?* O Learner Lab não dá as permissões de IAM para o driver de disco (EBS). Em produção seria um volume persistente ou um banco gerenciado.
