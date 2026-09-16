# FCG Notifications — Serverless

Substitui o container `NotificationsAPI` (que rodava 24/7 esperando eventos esporádicos) por uma **Azure Function** acionada diretamente pela fila RabbitMQ `PaymentProcessed`.

## Por que isso resolve o problema do TC

O container antigo consumia recursos computacionais o tempo todo, mesmo ocioso na maior parte do tempo. A Function roda em **Consumption Plan**: só é executada (e cobrada) quando uma mensagem chega na fila.

## Como funciona

- **Trigger:** [`RabbitMQTrigger`](NotificationFunction.cs) do pacote `Microsoft.Azure.WebJobs.Extensions.RabbitMQ` — um trigger real, não polling: o runtime se inscreve como consumidor AMQP da fila e a function é invocada a cada mensagem publicada.
- **Fila:** `PaymentProcessed`, a mesma fila que o `fcg-payments-api` já publica via MassTransit (`fcg-payments-api/src/FCG.PaymentsAPI/Consumers/OrderPlacedConsumer.cs`) — não foi criada uma fila nova só para o exercício.
- **Modelo:** *in-process* (`Microsoft.NET.Sdk.Functions`), porque o binding de trigger para RabbitMQ não existe no modelo isolated worker (só Storage Queue, Service Bus e Event Hub têm bindings isolated oficiais).

## Rodar localmente

Requer [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local) e RabbitMQ acessível (o `docker-compose.yml` da raiz já sobe um em `localhost:5672`).

```bash
dotnet build
func start
```

`local.settings.json` (não versionado) já aponta para `amqp://guest:guest@localhost:5672`.

## Deploy no Azure (IaC)

```bash
az group create --name rg-fcg-fase3 --location brazilsouth

az deployment group create \
  --resource-group rg-fcg-fase3 \
  --template-file infra/main.bicep \
  --parameters rabbitMqConnection="amqp://usuario:senha@seu-host:5672"

func azure functionapp publish <nome-da-function-app-gerado>
```

O Bicep cria: Storage Account (obrigatório para o runtime do Functions), Application Insights (logs centralizados), App Service Plan Consumption (Y1) e a Function App em Linux com o runtime .NET 8 in-process.

## Testar o fluxo completo

1. Suba a stack (`docker-compose up -d` na raiz do repo) e rode a function localmente (`func start`)
2. Faça uma compra real via Kong (`POST /api/auth/register` → `login` → fluxo de pedido → pagamento)
3. Quando o `payments-api` publicar `PaymentProcessedEvent`, os logs da function mostram:
   ```
   [NOTIFICACAO ENVIADA] Para usuario {userId} | Assunto: Pagamento aprovado! | ...
   ```
