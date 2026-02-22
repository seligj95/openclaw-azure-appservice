targetScope = 'subscription'

// ============================================================
// OpenClaw on Azure App Service — Main Infrastructure
// ============================================================

@minLength(1)
@maxLength(64)
@description('Name of the environment (used for resource naming)')
param environmentName string

@description('Primary location for all resources')
param location string

// --- Discord ---
@description('Discord bot token')
@secure()
param discordBotToken string = ''

@description('Comma-separated Discord user IDs allowed to DM the bot')
param discordAllowedUsers string = ''

// --- Telegram ---
@description('Telegram bot token (optional)')
@secure()
param telegramBotToken string = ''

@description('Telegram allowed user ID (optional)')
param telegramAllowedUserId string = ''

// --- OpenClaw config ---
@description('Gateway authentication token (auto-generated if empty)')
@secure()
param openclawGatewayToken string = ''

@description('OpenClaw AI model identifier (overridden when Azure OpenAI is enabled)')
param openclawModel string = ''

// --- Azure OpenAI ---
@description('Enable Azure OpenAI resource provisioning')
param enableAzureOpenAi bool = true

@description('Azure OpenAI model deployment name')
param azureOpenAiModelDeployment string = 'gpt-4o'

@description('Azure OpenAI model name')
param azureOpenAiModelName string = 'gpt-4o'

@description('Azure OpenAI model version')
param azureOpenAiModelVersion string = '2024-11-20'

@description('Azure OpenAI model capacity (TPM in thousands)')
param azureOpenAiModelCapacity int = 30

@description('Bot persona name')
param openclawPersonaName string = 'Clawd'

// --- App Service ---
@description('App Service Plan SKU')
param appServiceSkuName string = 'P0v4'

// --- Container ---
@description('Container image tag')
param imageTag string = 'latest'

// --- Security ---
@description('Comma-separated CIDR blocks for IP restrictions (empty = allow all)')
param allowedIpRanges string = ''

// --- Monitoring ---
@description('Enable Azure Monitor alerts')
param enableAlerts bool = true

@description('Email address for alert notifications')
param alertEmailAddress string = ''

// ============================================================
// Variables
// ============================================================

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

// Generate a gateway token if not provided
var gatewayToken = empty(openclawGatewayToken) ? 'gt-${uniqueString(subscription().id, environmentName, 'gateway')}' : openclawGatewayToken

// ============================================================
// Resource Group
// ============================================================

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${abbrs.resourcesResourceGroups}openclaw-${environmentName}'
  location: location
  tags: tags
}

// ============================================================
// Modules
// ============================================================

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
  }
}

module containerRegistry 'modules/container-registry.bicep' = {
  name: 'container-registry'
  scope: rg
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
  }
}

module storageAccount 'modules/storage-account.bicep' = {
  name: 'storage-account'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
  }
}

module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'app-service-plan'
  scope: rg
  params: {
    name: '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    skuName: appServiceSkuName
  }
}

module azureOpenAi 'modules/azure-openai.bicep' = if (enableAzureOpenAi) {
  name: 'azure-openai'
  scope: rg
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: location
    tags: tags
    modelDeploymentName: azureOpenAiModelDeployment
    modelName: azureOpenAiModelName
    modelVersion: azureOpenAiModelVersion
    modelCapacity: azureOpenAiModelCapacity
  }
}

module appService 'modules/app-service.bicep' = {
  name: 'app-service'
  scope: rg
  params: {
    name: '${abbrs.webSites}${resourceToken}'
    location: location
    tags: tags
    appServicePlanId: appServicePlan.outputs.id
    acrLoginServer: containerRegistry.outputs.loginServer
    acrId: containerRegistry.outputs.id
    imageTag: imageTag
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    storageAccountName: storageAccount.outputs.name
    storageAccountAccessKey: storageAccount.outputs.accessKey
    storageFileShareName: storageAccount.outputs.fileShareName
    discordBotToken: discordBotToken
    discordAllowedUsers: discordAllowedUsers
    telegramBotToken: telegramBotToken
    telegramAllowedUserId: telegramAllowedUserId
    openclawGatewayToken: gatewayToken
    openclawModel: openclawModel
    openclawPersonaName: openclawPersonaName
    allowedIpRanges: allowedIpRanges
    azureOpenAiEndpoint: enableAzureOpenAi ? azureOpenAi!.outputs.endpoint : ''
    azureOpenAiApiKey: enableAzureOpenAi ? azureOpenAi!.outputs.apiKey : ''
    azureOpenAiDeploymentName: enableAzureOpenAi ? azureOpenAi!.outputs.deploymentName : ''
  }
}

module alerts 'modules/alerts.bicep' = if (enableAlerts) {
  name: 'alerts'
  scope: rg
  params: {
    namePrefix: 'openclaw-${resourceToken}'
    webAppId: appService.outputs.id
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    alertEmailAddress: alertEmailAddress
    tags: tags
  }
}

// ============================================================
// Outputs (consumed by azd and scripts)
// ============================================================

output AZURE_RESOURCE_GROUP string = rg.name
output CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
output CONTAINER_REGISTRY_LOGIN_SERVER string = containerRegistry.outputs.loginServer
output WEBAPP_NAME string = appService.outputs.name
output WEBAPP_URL string = appService.outputs.url
output WEBAPP_HOSTNAME string = appService.outputs.defaultHostName
output STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
output AZURE_OPENAI_ENDPOINT string = enableAzureOpenAi ? azureOpenAi!.outputs.endpoint : ''
output AZURE_OPENAI_DEPLOYMENT_NAME string = enableAzureOpenAi ? azureOpenAi!.outputs.deploymentName : ''
