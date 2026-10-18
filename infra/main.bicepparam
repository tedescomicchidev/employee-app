using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'switzerlandnorth')
param modelName = readEnvironmentVariable('AZURE_MODEL_NAME', 'gpt-4.1')
param modelVersion = readEnvironmentVariable('AZURE_MODEL_VERSION', '2025-04-14')
param modelSkuName = readEnvironmentVariable('AZURE_MODEL_SKU', 'Standard')
param modelCapacity = int(readEnvironmentVariable('AZURE_MODEL_CAPACITY', '30'))
