param namespaceName string
param hubName string
param location string
param tags object

// ADR-008: Standard tier. APNs credentials are uploaded by the human (never via Bicep).
resource ns 'Microsoft.NotificationHubs/namespaces@2023-09-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    namespaceType: 'NotificationHub'
    zoneRedundancy: 'Enabled'
  }
}

resource hub 'Microsoft.NotificationHubs/namespaces/notificationHubs@2023-09-01' = {
  parent: ns
  name: hubName
  location: location
  tags: tags
  properties: {}
}

output namespaceName string = ns.name
output hubName string = hub.name
