using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'switzerlandnorth')
param modelName = readEnvironmentVariable('AZURE_MODEL_NAME', 'gpt-4o')
param modelVersion = readEnvironmentVariable('AZURE_MODEL_VERSION', '2024-11-20')
param modelSkuName = readEnvironmentVariable('AZURE_MODEL_SKU', 'GlobalStandard')
param modelCapacity = int(readEnvironmentVariable('AZURE_MODEL_CAPACITY', '30'))
param apiClientId = readEnvironmentVariable('API_CLIENT_ID', '')
param graphDirectory = readEnvironmentVariable('GRAPH_DIRECTORY', 'false')
param toolsClientId = readEnvironmentVariable('TOOLS_CLIENT_ID', '')
param apiImage = readEnvironmentVariable('SERVICE_API_IMAGE_NAME', '')
