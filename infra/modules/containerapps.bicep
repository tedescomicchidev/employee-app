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
// Non-secret Entra ids for token validation (api/app/config.py). Empty until the human registers employee-api.
param entraTenantId string
param apiClientId string
// Resource app that agent tool calls (MCP, /mcp) are validated against; see api/app/config.py.
param toolsClientId string = ''
// 'true' fills the employee directory from each signed-in user's own Graph profile (ADR-010). Needs the
// federated credential and Graph User.Read consent on employee-api first (docs/architecture/auth-flows.md).
param graphDirectory string = 'false'
// 'true': the directory is the tenant's employees (managed identity, Graph application permissions).
param graphDirectorySync string = 'false'
// Placeholder until `azd deploy` pushes the real api image (listens on 80 until then).
// After a deploy azd records SERVICE_API_IMAGE_NAME in its environment; main.bicepparam passes it back so a
// later `azd provision` keeps the deployed image instead of resetting the app to the placeholder.
param deployedImage string = ''
var image = empty(deployedImage) ? 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest' : deployedImage
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
            { name: 'ENTRA_TENANT_ID', value: entraTenantId }
            { name: 'API_CLIENT_ID', value: apiClientId }
            { name: 'TOOLS_CLIENT_ID', value: toolsClientId }
            { name: 'GRAPH_DIRECTORY', value: graphDirectory }
            { name: 'GRAPH_DIRECTORY_SYNC', value: graphDirectorySync }
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
