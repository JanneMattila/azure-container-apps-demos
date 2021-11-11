# Variables
$containerAppsEnvironment = "mycontainerenvironment"
$workspaceName = "aca-workspace"
$storageAccountName = "academos0000010"

$resourceGroup = "rg-containerapps-demo"
$location = "northeurope"

# Login to Azure
az login

# List subscriptions
az account list -o table

# *Explicitly* select your working context
az account set --subscription AzureDev

# Show current context
az account show -o table

# Prepare extensions and provider
az extension add --upgrade --yes --name log-analytics
az extension add --yes --source "https://workerappscliextension.blob.core.windows.net/azure-cli-extension/containerapp-0.2.0-py2.py3-none-any.whl"
az provider register --namespace Microsoft.Web

# Double check the registration
az provider show -n Microsoft.Web -o table

# Create new resource group
az group create --name $resourceGroup --location $location -o table

# Create Log Analytics workspace
$workspaceCustomerId = (az monitor log-analytics workspace create --resource-group $resourceGroup --workspace-name $workspaceName --query customerId -o tsv)
$workspaceKey = (az monitor log-analytics workspace get-shared-keys --resource-group $resourceGroup --workspace-name $workspaceName --query primarySharedKey -o tsv)
$workspaceCustomerId

# Create Container Apps environment
az containerapp env create `
  --name $containerAppsEnvironment `
  --resource-group $resourceGroup `
  --logs-workspace-id $workspaceCustomerId `
  --logs-workspace-key $workspaceKey `
  --location $location

####################
# Create App 1: Echo
####################
$echoAppFqdn = (az containerapp create `
  --name echo `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --image jannemattila/echo:latest `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --ingress "external" `
  --target-port 80 `
  --min-replicas 0 `
  --max-replicas 1 `
  --query latestRevisionFqdn -o tsv)

"https://$echoAppFqdn/"

$url = "https://$echoAppFqdn/api/echo"
$data = @{
    firstName = "John"
    lastName  = "Doe"
}
$body = ConvertTo-Json $data
Invoke-RestMethod -Body $body -ContentType "application/json" -Method "POST" -DisableKeepAlive -Uri $url

######################################
# Create App 2: Web app network tester
######################################

az storage account create `
  --name $storageAccountName `
  --resource-group $resourceGroup `
  --location $location `
  --sku Standard_LRS `
  --kind StorageV2

$storageKey = (az storage account keys list --resource-group $resourceGroup --account-name $storageAccountName --query '[0].value' --out tsv)

@"
- name: statestore
  type: state.azure.blobstorage
  version: v1
  metadata:
  - name: accountName
    value: $storageAccountName
  - name: accountKey
    value: $storageKey
  - name: containerName
    value: state
"@ > components.yaml

# json equivalent
@"
[
  {
    "name": "statestore",
    "type": "state.azure.blobstorage",
    "version": "v1",
    "metadata": [
      {
        "name": "accountName",
        "value": "$storageAccountName"
      },
      {
        "name": "accountKey",
        "value": "$storageKey"
      },
      {
        "name": "containerName",
        "value": "state"
      }
    ]
  }
]
"@ > components.json

$webAppNetworkAppFqdn = (az containerapp create `
  --name webapp-network-tester `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --image jannemattila/webapp-network-tester:latest `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --ingress "external" `
  --target-port 80 `
  --min-replicas 0 `
  --max-replicas 1 `
  --enable-dapr `
  --dapr-app-port 80 `
  --dapr-app-id webappnt `
  --dapr-components ./components.yaml `
  --query latestRevisionFqdn -o tsv)

"https://$webAppNetworkAppFqdn/"

$url2 = "https://$webAppNetworkAppFqdn/api/commands"

# Test that app is running succesfully
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
IPLOOKUP bing.com
"@

# Grab Dapr port from environment variable
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
INFO ENV DAPR_HTTP_PORT
"@

# Get "demo1" state content
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
HTTP GET http://localhost:3500/v1.0/state/statestore/demo1
"@

# Post "demo1" state content
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
HTTP POST http://dapr-app-id:webappnt@localhost:3500/v1.0/state/statestore
[{ "key": "demo1", "value": "Here is state value to be stored"}]
"@

# Query logs related to webapp-network-tester
az monitor log-analytics query `
  --workspace $workspaceCustomerId `
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'webapp-network-tester'" `
  --out table


###################
# Create App 3: CTB
###################
# Deploy image "1.0.56"
$ctbFqdn = (az containerapp create `
  --name ctb `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --image "jannemattila/catch-the-banana:1.0.56" `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --ingress "external" `
  --target-port 80 `
  --min-replicas 0 `
  --max-replicas 1 `
  --query latestRevisionFqdn -o tsv)

"https://$ctbFqdn/"

# Update with new revision and make it active right away
$ctbFqdn = (az containerapp update `
  --name ctb `
  --revisions-mode single `
  --resource-group $resourceGroup `
  --image "jannemattila/catch-the-banana:1.0.57" `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --ingress "external" `
  --target-port 80 `
  --min-replicas 0 `
  --max-replicas 1 `
  --query latestRevisionFqdn -o tsv)

"https://$ctbFqdn/"

# Wipe out the resources
az group delete --name $resourceGroup -y
