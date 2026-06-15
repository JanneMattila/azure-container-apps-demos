# Variables
$resourceGroup = "rg-sandboxes"
$location = "swedencentral"

$sandboxGroupName = "sandbox-group-1"

# Install Azure Container Apps CLI
irm https://aka.ms/aca-cli-install-ps | iex

# Check
aca version

# *Explicitly* select your working context
az account set --subscription "workload1-production-online"

# Show current context
$subscriptionId = az account show --query id -o tsv

# Create new resource group
az group create --name $resourceGroup --location $location -o table

# Create new Container App Sandbox Group
aca sandboxgroup create --name $sandboxGroupName --resource-group $resourceGroup -s $subscriptionId --location $location --set-config

# List available public disks
aca sandboxgroup disk list-public

# Create new Container App Sandbox
aca sandbox create `
 --disk ubuntu `
 --cpu 0.25 `
 --memory 0.5 `
 --traffic-inspection Partial `
 --egress-rule "pattern:Allow" `
 --label name=demo001

# Execute commands
aca sandbox exec -l name=demo001 --command "curl -d 'ACA Sandbox says hi!' https://echo.jannemattila.com/api/echo"

# Cleanup
aca sandbox delete -l name=demo001 --yes
aca sandboxgroup delete --name $sandboxGroupName --resource-group $resourceGroup --yes
az group delete --name $resourceGroup --yes --no-wait
