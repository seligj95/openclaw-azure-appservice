@description('Name of the virtual network')
param name string

@description('Location for the virtual network')
param location string = resourceGroup().location

@description('Tags for the virtual network')
param tags object = {}

@description('VNet address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('App Service integration subnet address prefix')
param appSubnetAddressPrefix string = '10.0.1.0/24'

@description('Private endpoints subnet address prefix')
param privateEndpointSubnetAddressPrefix string = '10.0.2.0/24'

@description('Deploy Azure OpenAI private DNS zone')
param enableOpenAiDnsZone bool = true

// --- NSGs ---

resource appSubnetNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${name}-app-nsg'
  location: location
  tags: tags
}

resource peSubnetNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${name}-pe-nsg'
  location: location
  tags: tags
}

// --- Virtual Network ---

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: appSubnetAddressPrefix
          networkSecurityGroup: {
            id: appSubnetNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.CognitiveServices'
            }
          ]
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          networkSecurityGroup: {
            id: peSubnetNsg.id
          }
        }
      }
    ]
  }
}

// --- Private DNS Zones ---

resource storageDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

resource openAiDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableOpenAiDnsZone) {
  name: 'privatelink.openai.azure.com'
  location: 'global'
  tags: tags
}

// --- VNet Links ---

resource storageDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storageDnsZone
  name: '${name}-storage-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource openAiDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableOpenAiDnsZone) {
  parent: openAiDnsZone
  name: '${name}-openai-link'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// --- Outputs ---

output vnetId string = vnet.id
output appSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output storagePrivateDnsZoneId string = storageDnsZone.id
output openAiPrivateDnsZoneId string = enableOpenAiDnsZone ? openAiDnsZone.id : ''
