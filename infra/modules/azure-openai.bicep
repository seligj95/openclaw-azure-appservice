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

@description('Subnet ID for the private endpoint')
param privateEndpointSubnetId string

@description('Private DNS zone ID for Azure OpenAI')
param privateDnsZoneId string

@description('App subnet ID for VNet rules (allows traffic via service endpoint)')
param appSubnetId string

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
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: appSubnetId
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
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

// --- Private Endpoint ---
// dependsOn modelDeployment to ensure the Cognitive Services account is fully
// provisioned (not just Accepted) before the PE is created.
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${name}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-pe-connection'
        properties: {
          privateLinkServiceId: openAi.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
  dependsOn: [
    modelDeployment
  ]
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-openai-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

@description('Primary API key for the Azure OpenAI resource')
#disable-next-line outputs-should-not-contain-secrets
output apiKey string = openAi.listKeys().key1
