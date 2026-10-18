// Infraestrutura como código para a Function App de notificações.
// Substitui o container NotificationsAPI (24/7) por uma Function
// Consumption Plan (paga só pela execução), acionada pela fila
// RabbitMQ "PaymentProcessed".
//
// Deploy:
//   az deployment group create \
//     --resource-group rg-fcg-fase3 \
//     --template-file main.bicep \
//     --parameters rabbitMqConnection="amqp://user:pass@host:5672"

@description('Nome base usado para derivar os nomes dos recursos (deve ser globalmente único para storage/function app).')
param appName string = 'fcgnotifications'

@description('Região do Azure onde os recursos serão criados.')
param location string = resourceGroup().location

@description('Connection string do RabbitMQ (AMQP). Passar via --parameters ou Key Vault reference, nunca hardcoded.')
@secure()
param rabbitMqConnection string

var storageAccountName = toLower('${appName}st${uniqueString(resourceGroup().id)}')
var functionAppName = '${appName}-func-${uniqueString(resourceGroup().id)}'
var appServicePlanName = '${appName}-plan'
var appInsightsName = '${appName}-ai'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// Consumption plan (Y1): paga só pelas execuções, sem custo ocioso -
// exatamente o problema que o TC pede para resolver (NotificationsAPI
// rodando 24/7 para tarefa esporádica).
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Linux
  }
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      // "DOTNET|8.0" (modelo in-process), nao "DOTNET-ISOLATED": o
      // pacote Microsoft.Azure.WebJobs.Extensions.RabbitMQ so funciona
      // no modelo classico in-process.
      linuxFxVersion: 'DOTNET|8.0'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          // Obrigatorio para rodar .NET 8 no modelo in-process (o Core Tools
          // avisa disso no "func start"). Sem isso o host nao carrega a app.
          name: 'FUNCTIONS_INPROC_NET8_ENABLED'
          value: '1'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          // Referencia direta por parametro seguro; em producao,
          // preferir @Microsoft.KeyVault(...) apontando para um Key Vault.
          name: 'RabbitMQConnection'
          value: rabbitMqConnection
        }
      ]
    }
  }
}

output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
