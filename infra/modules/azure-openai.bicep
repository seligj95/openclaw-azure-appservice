@description('Name of the Azure OpenAI resource')
param name string

@description('Location for the resource')
param location string = resourceGroup().location

@description('Tags for the resource')
param tags object = {}

@description('OpenAI model deployment name')
param modelDeploymentName string = 'gpt-4o'

@description('OpenAI model name')
param modelName string = 'gpt-4o'

@description('OpenAI model version')
param modelVersion string = '2024-11-20'

@description('Model deployment capacity (TPM in thousands)')
param modelCapacity int = 30

@description('Managed Identity principal ID for Cognitive Services OpenAI User role')
param openAiUserPrincipalId string = ''

// --- Azure OpenAI (Cognitive Services) resource ---
resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// --- Model deployment ---
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAi
  name: modelDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

// --- Grant managed identity Cognitive Services OpenAI User role (if principal provided) ---
resource openAiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(openAiUserPrincipalId)) {
  name: guid(openAi.id, openAiUserPrincipalId, 'CognitiveServicesOpenAIUser')
  scope: openAi
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: openAiUserPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output id string = openAi.id
output name string = openAi.name
output endpoint string = openAi.properties.endpoint
output deploymentName string = modelDeployment.name
@description('Primary API key for the Azure OpenAI resource')
#disable-next-line outputs-should-not-contain-secrets
output apiKey string = openAi.listKeys().key1
