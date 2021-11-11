# Change at least this!
$yourName = "janne"

# Other variables
$containerAppsEnvironment = "mycontainerenvironment"
$workspaceName = "aca-workspace"

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

# Prepare extension and provider
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

# Wipe out the resources
az group delete --name $resourceGroup -y
