@description('Name of the storage account')
param name string

@description('Location for the storage account')
param location string = resourceGroup().location

@description('Tags for the storage account')
param tags object = {}

@description('Name of the file share for OpenClaw workspace')
param fileShareName string = 'openclaw-workspace'

@description('File share quota in GB')
param fileShareQuota int = 5

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    shareQuota: fileShareQuota
    accessTier: 'TransactionOptimized'
  }
}

output id string = storageAccount.id
output name string = storageAccount.name
output fileShareName string = fileShare.name

#disable-next-line outputs-should-not-contain-secrets
output accessKey string = storageAccount.listKeys().keys[0].value
