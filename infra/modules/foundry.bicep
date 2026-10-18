param name string
param projectName string
param location string
param tags object
param modelName string
param modelVersion string
param modelSkuName string
param modelCapacity int

resource account 'Microsoft.CognitiveServices/accounts@2026-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    allowProjectManagement: true
    customSubDomainName: name
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2026-05-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: 'Employee App (${projectName})'
    description: 'Employee App PoC Foundry project'
  }
}

resource model 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' = {
  parent: account
  name: modelName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
  dependsOn: [project]
}

output accountName string = account.name
output projectName string = project.name
output projectEndpoint string = 'https://${name}.services.ai.azure.com/api/projects/${project.name}'
output modelDeploymentName string = model.name
