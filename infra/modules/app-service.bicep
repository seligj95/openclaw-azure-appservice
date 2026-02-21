@description('Name of the Web App')
param name string

@description('Location for the Web App')
param location string = resourceGroup().location

@description('Tags for the Web App')
param tags object = {}

@description('App Service Plan resource ID')
param appServicePlanId string

@description('Container Registry login server (e.g., myacr.azurecr.io)')
param acrLoginServer string

@description('Container Registry resource ID')
param acrId string

@description('Container image tag')
param imageTag string = 'latest'

@description('Log Analytics workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

// --- Storage mount parameters ---
@description('Azure Storage account name for workspace mount')
param storageAccountName string

@description('Azure Storage account access key')
@secure()
param storageAccountAccessKey string

@description('Azure Files share name for workspace')
param storageFileShareName string

// --- OpenClaw configuration ---
@description('OpenRouter API key')
@secure()
param openRouterApiKey string

@description('Discord bot token')
@secure()
param discordBotToken string = ''

@description('Comma-separated Discord user IDs allowed to DM the bot')
param discordAllowedUsers string = ''

@description('Telegram bot token')
@secure()
param telegramBotToken string = ''

@description('Telegram allowed user ID')
param telegramAllowedUserId string = ''

@description('Gateway authentication token')
@secure()
param openclawGatewayToken string

@description('OpenClaw model identifier')
param openclawModel string = 'openrouter/anthropic/claude-3.5-sonnet'

@description('OpenClaw persona name')
param openclawPersonaName string = 'Clawd'

// --- Security ---
@description('Comma-separated CIDR blocks for IP restrictions (empty = allow all)')
param allowedIpRanges string = ''

// --- Managed Identity ---
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${name}'
  location: location
  tags: tags
}

// Grant managed identity AcrPull on the container registry
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrId, managedIdentity.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reference the existing ACR to scope the role assignment
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: split(acrLoginServer, '.')[0]
}

// --- Build IP restrictions ---
var ipRangesList = empty(allowedIpRanges) ? [] : split(allowedIpRanges, ',')
var ipRestrictions = [for (range, i) in ipRangesList: {
  ipAddress: trim(range)
  action: 'Allow'
  priority: 100 + i
  name: 'AllowedRange${i}'
}]
// When IP restrictions are set, add a deny-all rule at the end
var denyAllRule = empty(allowedIpRanges) ? [] : [
  {
    ipAddress: 'Any'
    action: 'Deny'
    priority: 2147483647
    name: 'DenyAll'
  }
]
var allIpRestrictions = concat(ipRestrictions, denyAllRule)

// --- Build app settings ---
var baseAppSettings = [
  { name: 'WEBSITES_PORT', value: '18789' }
  { name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE', value: 'true' }
  { name: 'NODE_ENV', value: 'production' }
  { name: 'OPENROUTER_API_KEY', value: openRouterApiKey }
  { name: 'OPENCLAW_GATEWAY_TOKEN', value: openclawGatewayToken }
  { name: 'OPENCLAW_MODEL', value: openclawModel }
  { name: 'OPENCLAW_PERSONA_NAME', value: openclawPersonaName }
  { name: 'OPENCLAW_WORKSPACE', value: '/mnt/openclaw-workspace' }
  { name: 'GATEWAY_PORT', value: '18789' }
]

var discordSettings = empty(discordBotToken) ? [] : [
  { name: 'DISCORD_BOT_TOKEN', value: discordBotToken }
  { name: 'DISCORD_ALLOWED_USERS', value: discordAllowedUsers }
]

var telegramSettings = empty(telegramBotToken) ? [] : [
  { name: 'TELEGRAM_BOT_TOKEN', value: telegramBotToken }
  { name: 'TELEGRAM_ALLOWED_USER_ID', value: telegramAllowedUserId }
]

var appSettings = concat(baseAppSettings, discordSettings, telegramSettings)

// --- Web App ---
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrLoginServer}/openclaw:${imageTag}'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: managedIdentity.properties.clientId
      alwaysOn: true
      webSocketsEnabled: true
      healthCheckPath: '/health'
      appSettings: appSettings
      ipSecurityRestrictions: empty(allIpRestrictions) ? null : allIpRestrictions
      azureStorageAccounts: {
        openclawworkspace: {
          type: 'AzureFiles'
          accountName: storageAccountName
          shareName: storageFileShareName
          mountPath: '/mnt/openclaw-workspace'
          accessKey: storageAccountAccessKey
        }
      }
    }
  }
  dependsOn: [
    acrPullRoleAssignment
  ]
}

// --- Diagnostics ---
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${name}-diagnostics'
  scope: webApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = webApp.id
output name string = webApp.name
output defaultHostName string = webApp.properties.defaultHostName
output url string = 'https://${webApp.properties.defaultHostName}'
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityClientId string = managedIdentity.properties.clientId
