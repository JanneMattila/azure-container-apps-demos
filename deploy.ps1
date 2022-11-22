# Variables
$containerAppsEnvironment = "mycontainerenvironment"
$workspaceName = "aca-workspace"
$storageAccountName = "academos00000100"
$acrName = "myacaacr0000010"

$resourceGroup = "rg-containerapps-demos"
$location = "northeurope"

# Login to Azure
az login -t 8a35e8cd-119a-4446-b762-5002cf925b1d

# List subscriptions
az account list -o table

# *Explicitly* select your working context
az account set --subscription development

# Show current context
az account show -o table

# Prepare extensions and provider
az extension add --upgrade --yes --name log-analytics
az extension add --name containerapp --upgrade --yes
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights

# Double check the registration
az provider show -n Microsoft.App -o table

# Create new resource group
az group create --name $resourceGroup --location $location -o table

# Create container registry
$acr = (az acr create -l $location -g $resourceGroup -n $acrName --sku Basic -o json) | ConvertFrom-Json
$acr

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
az containerapp create `
  --name echo `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --image jannemattila/echo:latest `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --ingress "external" `
  --target-port 80 `
  --min-replicas 0 `
  --max-replicas 1

# If you want to fetch existing container app details
$echoAppFqdn = (az containerapp show --name echo --resource-group $resourceGroup --query properties.latestRevisionFqdn -o tsv)

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
componentType: state.azure.blobstorage
version: v1
metadata:
- name: accountName
  value: $storageAccountName
- name: accountKey
  value: $storageKey
- name: containerName
  value: state
scopes:
- webappnt
"@ > components.yaml

az containerapp env dapr-component set --name $containerAppsEnvironment --resource-group $resourceGroup --dapr-component-name statestore --yaml "./components.yaml"

az containerapp create `
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
  --system-assigned `
  --dapr-app-port 80 `
  --dapr-app-id webappnt

# If you want to fetch existing container app details
$webAppNetworkAppFqdn = (az containerapp show --name webapp-network-tester --resource-group $resourceGroup --query properties.latestRevisionFqdn -o tsv)

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
Invoke-RestMethod -Method "POST" -ContentType "text/plain" -DisableKeepAlive -Uri $url2 -Body @"
HTTP POST http://localhost:3500/v1.0/state/statestore
[{ "key": "demo1", "value": "Here is state value to be stored 1"}]
"@

#
# Managed identity example:
# - Note demo does not enable identity but for information purposes
# 1. Fetch IDENTITY_HEADER (it's guid)
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
INFO ENV IDENTITY_HEADER
"@

# Request token using specific client id and *set* identity header as seen in above:
Invoke-RestMethod -Method "POST" -ContentType "text/plain" -DisableKeepAlive -Uri $url2 -Body @"
HTTP GET "http://localhost:42356/msi/token?api-version=2019-08-01&resource=https://management.azure.com/" "X-IDENTITY-HEADER=<guid above here>"
"@

# Query logs related to webapp-network-tester
az monitor log-analytics query `
  --workspace $workspaceCustomerId `
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'webapp-network-tester'" `
  --out table

###################
# Create App 3: CTB
###################
az containerapp create `
  --name ctb `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --image "jannemattila/catch-the-banana:1.0.67" `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --ingress "external" `
  --enable-dapr `
  --dapr-app-port 80 `
  --dapr-app-id ctb `
  --target-port 80 `
  --min-replicas 0 `
  --max-replicas 1

# If you want to fetch existing container app details
$ctbFqdn = (az containerapp show --name ctb --resource-group $resourceGroup --query properties.latestRevisionFqdn -o tsv)

"https://$ctbFqdn/"

# Update with new revision and make it active right away
$ctbFqdn = (az containerapp update `
    --name ctb `
    --resource-group $resourceGroup `
    --image "jannemattila/catch-the-banana:1.0.67" `
    --cpu "0.25" `
    --memory "0.5Gi" `
    --min-replicas 0 `
    --max-replicas 1 `
    --query properties.latestRevisionFqdn -o tsv)

"https://$ctbFqdn/"

###########################
# Create App 4: Blanko app
###########################

az containerapp up --name blankoapp --source ./blankoapp --ingress external --target-port 80 --environment $containerAppsEnvironment

$blankoFqdn = (az containerapp show -n blankoapp -g $resourceGroup --query properties.latestRevisionFqdn -o tsv)

"https://$blankoFqdn/"

az containerapp logs show -n blankoapp -g $resourceGroup --follow

az containerapp exec -n blankoapp -g $resourceGroup

#####################################
# Create App 5: Azure automation app
#####################################

# Create identity
$automationidentity = (az identity create --name id-automation --resource-group $resourceGroup -o json) | ConvertFrom-Json
$automationidentity

# Assign "Reader" role for subscription
$subscription = (az account show -o tsv --query id)
az role assignment create --role "Reader" --assignee $automationidentity.clientId --scope /subscriptions/$subscription

# Assign "AcrPull" for our container registry
az role assignment create --role "AcrPull" --assignee $automationidentity.clientId --scope $acr.id

# Build automation app
az acr build --registry $acrName --image "az-aca-demo:v1" --output json azureautomationapp/.

# Create Dapr configuration
az containerapp env dapr-component set --name $containerAppsEnvironment --resource-group $resourceGroup --dapr-component-name automation --yaml "./azureautomationapp/dapr.yaml"

# Login to ACR (requires Docker daemon)
az acr update -n $acrName --admin-enabled true
az acr login --name $acrName
# Login to ACR (doesn't require Docker daemon)
az acr login --name $acrName --expose-token

# Create automation app
az containerapp create `
  --name azureautomationapp `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --image "$($acr.loginServer)/az-aca-demo:v1" `
  --registry-server $acr.loginServer `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --dapr-app-id automation `
  --user-assigned $automationidentity.id `
  --env-vars AZURE_CLIENT_ID=$($automationidentity.clientId) `
  --min-replicas 0 `
  --max-replicas 1

$containerapp_id = (az containerapp show --name azureautomationapp --resource-group $resourceGroup --query id -o tsv)
$containerapp_id

# Add cron scaling rule: 6:00 AM-6:10 AM daily (https://crontab.guru)
az rest --method GET --uri "$($containerapp_id)?api-version=2022-03-01"
az rest --method GET --uri "$($containerapp_id)?api-version=2022-03-01" --query properties.template.scale.rules
az rest --method PATCH --uri "$($containerapp_id)?api-version=2022-03-01" --body @azureautomationapp/rules.json

az containerapp logs show -n azureautomationapp -g $resourceGroup --follow

# Query logs related to azureautomationapp
az monitor log-analytics query `
  --workspace $workspaceCustomerId `
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'azureautomationapp' | project TimeGenerated, Log_s | order by TimeGenerated desc | take 20 | order by TimeGenerated asc" `
  --out table

# Wipe out the resources
az group delete --name $resourceGroup -y
