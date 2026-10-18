targetScope = 'subscription'

@minLength(1)
@maxLength(32)
@description('azd environment name, e.g. dev')
param environmentName string

@description('ADR-001: all resources live in Switzerland North.')
@allowed(['switzerlandnorth'])
param location string = 'switzerlandnorth'

param modelName string = 'gpt-4.1'
param modelVersion string = '2025-04-14'
param modelSkuName string = 'Standard'
param modelCapacity int = 30

var tags = {
  'azd-env-name': environmentName
  app: 'employee-app'
}
var token = toLower(uniqueString(subscription().id, environmentName, location))
var rgName = 'rg-employee-${environmentName}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: { name: 'emp-${token}', location: location, tags: tags }
}

module registry 'modules/registry.bicep' = {
  scope: rg
  name: 'registry'
  params: { name: 'acr${token}', location: location, tags: tags }
}

module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity'
  params: { name: 'id-api-${token}', location: location, tags: tags }
}

module foundry 'modules/foundry.bicep' = {
  scope: rg
  name: 'foundry'
  params: {
    name: 'aif-${token}'
    projectName: 'employee-${environmentName}'
    location: location
    tags: tags
    modelName: modelName
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
  }
}

module cosmos 'modules/cosmos.bicep' = {
  scope: rg
  name: 'cosmos'
  params: { name: 'cosmos-${token}', location: location, tags: tags }
}

module keyVault 'modules/keyvault.bicep' = {
  scope: rg
  name: 'keyvault'
  params: { name: 'kv-${token}', location: location, tags: tags }
}

module notificationHub 'modules/notificationhub.bicep' = {
  scope: rg
  name: 'notificationhub'
  params: {
    namespaceName: 'nhns-${token}'
    hubName: 'nh-employee-${environmentName}'
    location: location
    tags: tags
  }
}

module containerApps 'modules/containerapps.bicep' = {
  scope: rg
  name: 'containerapps'
  params: {
    name: 'ca-api-${token}'
    environmentName: 'cae-${token}'
    location: location
    tags: tags
    workspaceName: monitoring.outputs.workspaceName
    appInsightsName: monitoring.outputs.appInsightsName
    registryName: registry.outputs.name
    identityId: identity.outputs.id
    identityClientId: identity.outputs.clientId
    cosmosEndpoint: cosmos.outputs.endpoint
    cosmosDatabase: cosmos.outputs.databaseName
    keyVaultUri: keyVault.outputs.uri
    foundryProjectEndpoint: foundry.outputs.projectEndpoint
  }
}

module rbac 'modules/rbac.bicep' = {
  scope: rg
  name: 'rbac'
  params: {
    principalId: identity.outputs.principalId
    registryName: registry.outputs.name
    keyVaultName: keyVault.outputs.name
    cosmosName: cosmos.outputs.name
    foundryAccountName: foundry.outputs.accountName
    foundryProjectName: foundry.outputs.projectName
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output AZURE_API_URL string = containerApps.outputs.apiUrl
output AZURE_AI_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
