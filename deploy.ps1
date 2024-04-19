# Variables
$containerAppsEnvironment = "containerenvironment"
$workspaceName = "aca-workspace"
$storageAccountName = "academos00000100"
$shareName = "share"
$vnetName = "vnet-aca"
$acrName = "myacaacr0000010"
$worloadProfileName = "dedicated1"

$resourceGroup = "rg-containerapps-demos"
$location = "swedencentral"

# Login to Azure
az login --tenant $env:CONTOSO_TENANT_ID

# List subscriptions
az account list -o table

# *Explicitly* select your working context
az account set --subscription "development"

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

az network vnet create --name $vnetName --resource-group $resourceGroup --location $location --address-prefixes "10.0.0.0/16"

$subnetId = $(az network vnet subnet create --name "aca-subnet" --vnet-name $vnetName --resource-group $resourceGroup --address-prefixes "10.0.1.0/24" --delegations "Microsoft.App/environments" --query id -o tsv)
$subnetId

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
  --infrastructure-subnet-resource-id $subnetId `
  --logs-workspace-id $workspaceCustomerId `
  --logs-workspace-key $workspaceKey `
  --enable-workload-profiles `
  --location $location

az containerapp env workload-profile list-supported `
  --location $location `
  --query "[].{Name: name, Cores: properties.cores, MemoryGiB: properties.memoryGiB, Category: properties.category}" `
  -o table

# Add/Edit profile
az containerapp env workload-profile add `
  --name $containerAppsEnvironment `
  --resource-group $resourceGroup `
  --workload-profile-type "D4" `
  --workload-profile-name $worloadProfileName `
  --min-nodes 0  `
  --max-nodes 1

# Delete profile
# az containerapp env workload-profile delete `
#   --name $containerAppsEnvironment `
#   --resource-group $resourceGroup `
#   --workload-profile-type "Dedicated-D4" `
#   --workload-profile-name $worloadProfileName

####################
# Create App 1: Echo
####################
az containerapp create `
  --name echo `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --image jannemattila/echo:1.0.118 `
  --env-vars ASPNETCORE_URLS="http://*:80" `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --ingress "external" `
  --target-port 80 `
  --min-replicas 0 `
  --max-replicas 1 `
  --workload-profile-name "Consumption"

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
  --image jannemattila/webapp-network-tester:1.0.69 `
  --env-vars ASPNETCORE_URLS="http://*:80" `
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

# Test that app is running succesfully
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
INFO ENV
"@

# Resolve other service
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
IPLOOKUP echo
"@

# Invoke other service
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
HTTP GET http://echo/
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
Invoke-RestMethod -Method "POST" -DisableKeepAlive -Uri $url2 -Body @"
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
  --max-replicas 1 `
  --workload-profile-name $workloadProfileName

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

# Build automation app - Azure CLI
$imageTag = (Get-Date -Format "yyyyMMddHHmmss")
az acr build --registry $acrName --image "az-aca-demo-cli:$imageTag" --output json azureautomationapp-cli/.

# Create automation app - Azure CLI
$secrets = "example1=value1", "example2=value2"
az containerapp job create `
  --name azureautomationapp `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --image "$($acr.loginServer)/az-aca-demo-cli:$imageTag" `
  --registry-server $acr.loginServer `
  --cpu "0.25" `
  --memory "0.5Gi" `
  --trigger-type "Schedule" `
  --cron-expression "0 6 * * *" `
  --mi-user-assigned $automationidentity.id `
  --registry-identity $automationidentity.id `
  --env-vars AZURE_CLIENT_ID=$($automationidentity.clientId) `
  --secrets $secrets

$containerapp_id = (az containerapp show --name azureautomationapp --resource-group $resourceGroup --query id -o tsv)
$containerapp_id

az containerapp logs show -n azureautomationapp -g $resourceGroup --follow

# Query logs related to azureautomationapp
az monitor log-analytics query `
  --workspace $workspaceCustomerId `
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'azureautomationapp' | project TimeGenerated, Log_s | order by TimeGenerated desc | take 20 | order by TimeGenerated asc" `
  --out table

# Same but with PowerShell:
# Optionally create SMB storage for PowerShell script
az storage share-rm create `
  --access-tier Hot `
  --enabled-protocols SMB `
  --quota 10 `
  --name $shareName `
  --storage-account $storageAccountName

# Build automation app - Azure PowerShell
$imageTag = (Get-Date -Format "yyyyMMddHHmmss")
az acr build --registry $acrName --image "az-aca-demo-pwsh:$imageTag" --output json azureautomationapp-pwsh/.

$environmentId = $(az containerapp env show `
    --name $containerAppsEnvironment `
    --resource-group $resourceGroup `
    --query id -o tsv)

# Create automation app - Azure PowerShell
# $envVars = "AZURE_CLIENT_ID=$($automationidentity.clientId)", "SCRIPT_FILE=/scripts/timer1.ps1"
# az containerapp job create `
#   --name azureautomationapppwsh `
#   --resource-group $resourceGroup `
#   --environment $containerAppsEnvironment `
#   --image "$($acr.loginServer)/az-aca-demo-pwsh:$imageTag" `
#   --registry-server $acr.loginServer `
#   --cpu "0.25" `
#   --memory "0.5Gi" `
#   --trigger-type "Schedule" `
#   --cron-expression "0 12 * * *" `
#   --mi-user-assigned $automationidentity.id `
#   --registry-identity $automationidentity.id `
#   --env-vars $envVars

@"
type: Microsoft.App/jobs
identity:
  type: UserAssigned
  userAssignedIdentities:
    ? $($automationidentity.id)
    : clientId: $($automationidentity.clientId)
      principalId: $($automationidentity.principalId)
properties:
  workloadProfileName: Consumption
  environmentId: $environmentId
  configuration:
    registries:
      - identity: $($automationidentity.id)
        server: $($acr.loginServer)
    replicaRetryLimit: 0
    replicaTimeout: 1800
    triggerType: Schedule
    scheduleTriggerConfig:
      cronExpression: 0 12 * * *
      parallelism: 1
      replicaCompletionCount: 1
  template:
    containers:
      - env:
          - name: AZURE_CLIENT_ID
            value: $($automationidentity.clientId)
          - name: SCRIPT_FILE
            value: /scripts/timer1.ps1
        image: $($acr.loginServer)/az-aca-demo-pwsh:$imageTag
        name: azureautomationapppwsh
        resources:
          cpu: 0.25
          memory: 0.5Gi
        volumeMounts:
          - mountPath: /scripts
            volumeName: azure-files-volume
    volumes:
      - name: azure-files-volume
        storageName: share
        storageType: AzureFile
"@ > app.yaml

# Pass script to the container
# - Upload example script
az storage file upload --source timer1.ps1 --share-name $shareName --path timer1.ps1 --account-name $storageAccountName --auth-mode key
# - Add storage to the environment
az containerapp env storage set `
  --name $containerAppsEnvironment `
  --resource-group $resourceGroup `
  --storage-name share `
  --azure-file-account-name $storageAccountName `
  --azure-file-account-key $storageKey `
  --azure-file-share-name $shareName `
  --access-mode ReadWrite

# az containerapp job show --name azureautomationapppwsh `
#   --resource-group $resourceGroup -o yaml > app2.yaml

# Add volume configuration to the app2.yaml
<#
      volumeMounts:
      - volumeName: azure-files-volume
        mountPath: /scripts
    volumes:
    - name: azure-files-volume
      storageType: AzureFile
      storageName: share
  #>

az containerapp job create --name azureautomationapppwsh `
  --resource-group $resourceGroup `
  --yaml app.yaml

az containerapp job start `
  --name azureautomationapppwsh `
  --resource-group $resourceGroup

az containerapp job execution list `
  --name azureautomationapppwsh `
  --resource-group $resourceGroup `
  --query '[].{Status: properties.status, Name: name, StartTime: properties.startTime}' `
  --output table

$lastJob = $(az containerapp job execution list `
    --name azureautomationapppwsh `
    --resource-group $resourceGroup `
    --query '[].{Name: name}[0]' `
    --output tsv)
$lastJob

az monitor log-analytics query `
  --workspace $workspaceCustomerId `
  --analytics-query @"
ContainerAppConsoleLogs_CL | where ContainerGroupName_s startswith '$lastJob' | order by _timestamp_d asc" --query "[].Log_s
"@ --out table

########################
# Same with share image
########################

@"
type: Microsoft.App/jobs
identity:
  type: UserAssigned
  userAssignedIdentities:
    ? $($automationidentity.id)
    : clientId: $($automationidentity.clientId)
      principalId: $($automationidentity.principalId)
properties:
  workloadProfileName: Consumption
  environmentId: $environmentId
  configuration:
    replicaRetryLimit: 0
    replicaTimeout: 1800
    triggerType: Schedule
    scheduleTriggerConfig:
      cronExpression: 0 12 * * *
      parallelism: 1
      replicaCompletionCount: 1
  template:
    containers:
      - env:
          - name: AZURE_CLIENT_ID
            value: $($automationidentity.clientId)
          - name: SCRIPT_FILE
            value: /scripts/timer1.ps1
        image: jannemattila/azure-powershell-job:1.0.4
        name: azure-powershell-job
        resources:
          cpu: 0.25
          memory: 0.5Gi
        volumeMounts:
          - mountPath: /scripts
            volumeName: azure-files-volume
    volumes:
      - name: azure-files-volume
        storageName: share
        storageType: AzureFile
"@ > azure-powershell-job.yaml

az containerapp job create --name azure-powershell-job `
  --resource-group $resourceGroup `
  --yaml azure-powershell-job.yaml

az containerapp job start `
  --name azure-powershell-job `
  --resource-group $resourceGroup

az containerapp job execution list `
  --name azure-powershell-job `
  --resource-group $resourceGroup `
  --query '[].{Status: properties.status, Name: name, StartTime: properties.startTime}' `
  --output table

$lastJob = $(az containerapp job execution list `
    --name azure-powershell-job `
    --resource-group $resourceGroup `
    --query '[].{Name: name}[0]' `
    --output tsv)
$lastJob

az monitor log-analytics query `
  --workspace $workspaceCustomerId `
  --analytics-query @"
ContainerAppConsoleLogs_CL | where ContainerGroupName_s startswith '$lastJob' | order by TimeGenerated asc" --query "[].Log_s
"@ --out table

# Wipe out the resources
az group delete --name $resourceGroup -y
