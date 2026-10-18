param name string
param environmentName string
param location string
param tags object
param workspaceName string
param appInsightsName string
param registryName string
param identityId string
param identityClientId string
param cosmosEndpoint string
param cosmosDatabase string
param keyVaultUri string
param foundryProjectEndpoint string
// Placeholder until `azd deploy` pushes the real api image (listens on 80 until then).
param image string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param targetPort int = 80

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource environment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
  }
}

resource environmentLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: environment
  name: 'to-law'
  properties: {
    workspaceId: workspace.id
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
  }
}

resource api 'Microsoft.App/containerApps@2025-01-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': 'api' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identityId}': {} }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: identityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: image
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: [
            { name: 'AZURE_CLIENT_ID', value: identityClientId }
            { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'COSMOS_DATABASE', value: cosmosDatabase }
            { name: 'KEY_VAULT_URI', value: keyVaultUri }
            { name: 'FOUNDRY_PROJECT_ENDPOINT', value: foundryProjectEndpoint }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output apiName string = api.name
output apiUrl string = 'https://${api.properties.configuration.ingress.fqdn}'
