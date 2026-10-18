param name string
param location string
param tags object
param databaseName string = 'employee'

// ADR-007: name -> partition key path. TTLs are not set yet (U-05 open).
var containers = [
  { name: 'employees', pk: '/oid' }
  { name: 'user_settings', pk: '/oid' }
  { name: 'vacation', pk: '/oid' }
  { name: 'vacation_params', pk: '/oid' }
  { name: 'config', pk: '/type' }
  { name: 'announcements', pk: '/id' }
  { name: 'announcement_inbox', pk: '/oid' }
  { name: 'confirmations', pk: '/oid' }
  { name: 'participants', pk: '/participant_id' }
  { name: 'events', pk: '/participant_id' }
]

resource account 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [{ name: 'EnableServerless' }]
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: true
      }
    ]
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    backupPolicy: {
      type: 'Continuous'
      continuousModeProperties: { tier: 'Continuous7Days' }
    }
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-04-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: { id: databaseName }
  }
}

resource sqlContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2025-04-15' = [for c in containers: {
  parent: database
  name: c.name
  properties: {
    resource: {
      id: c.name
      partitionKey: {
        paths: [c.pk]
        kind: 'Hash'
        version: 2
      }
    }
  }
}]

output name string = account.name
output endpoint string = account.properties.documentEndpoint
output databaseName string = database.name
