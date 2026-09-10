$containerAppsEnvironment = "containerenvironment"
$storageAccountName = "academos00000101"
$queueName = "queue01"
$vnetName = "vnet-aca"
$acrName = "myacaacr0000010"
$workloadProfileName = "dedicated1"
$jobName = "queue-timer1"
$identityName = "$jobName-identity"
$imageName = "queue-timer1:$(Get-Date -Format 'yyyyMMddHHmmss')"
$privateEndpointName = "$storageAccountName-queue-pe"
$privateDnsZoneName = "privatelink.queue.core.windows.net"
$disablePublicNetworkAccess = $false

$expectedRunTimeSeconds = 9 * 60 * 60
$replicaTimeoutSeconds = $expectedRunTimeSeconds + (60 * 60)
$visibilityTimeoutSeconds = $replicaTimeoutSeconds + (60 * 60)
$replicaRetryLimit = 0
$pollingIntervalSeconds = 60
$maxExecutions = 1

$resourceGroup = "rg-containerapps-demos"
$location = "swedencentral"

az extension add --name containerapp --upgrade --yes

$subscriptionId = az account show --query id -o tsv
$resourceGroupId = az group show --name $resourceGroup --query id -o tsv
$vnetId = az network vnet show --name $vnetName --resource-group $resourceGroup --query id -o tsv
$environmentSubnetId = az containerapp env show --name $containerAppsEnvironment --resource-group $resourceGroup --query properties.vnetConfiguration.infrastructureSubnetId -o tsv
if (-not $environmentSubnetId -or -not $environmentSubnetId.StartsWith("$vnetId/subnets/", [StringComparison]::OrdinalIgnoreCase)) {
  throw "The Container Apps environment must use a subnet in $vnetName to reach the queue private endpoint."
}

$peSubnetId = $(az network vnet subnet create --name "pe-subnet" --vnet-name $vnetName --resource-group $resourceGroup --address-prefixes "10.0.3.0/24" --query id -o tsv)

az network vnet subnet update `
  --ids $peSubnetId `
  --private-endpoint-network-policies Disabled

az containerapp env workload-profile add `
  --name $containerAppsEnvironment `
  --resource-group $resourceGroup `
  --workload-profile-type "D4" `
  --workload-profile-name $workloadProfileName `
  --min-nodes 0  `
  --max-nodes 1

az storage account create `
  --name $storageAccountName `
  --resource-group $resourceGroup `
  --location $location `
  --sku Standard_LRS `
  --kind StorageV2

$storageAccountId = az storage account show --name $storageAccountName --resource-group $resourceGroup --query id -o tsv

az rest `
  --method put `
  --url "https://management.azure.com${storageAccountId}/queueServices/default/queues/${queueName}?api-version=2023-05-01" `
  --body "{}"

az network private-endpoint create `
  --name $privateEndpointName `
  --resource-group $resourceGroup `
  --location $location `
  --subnet $peSubnetId `
  --private-connection-resource-id $storageAccountId `
  --group-id queue `
  --connection-name "$privateEndpointName-connection"

az network private-dns zone create `
  --resource-group $resourceGroup `
  --name $privateDnsZoneName

az network private-dns link vnet create `
  --resource-group $resourceGroup `
  --zone-name $privateDnsZoneName `
  --name "$vnetName-queue-link" `
  --virtual-network $vnetId `
  --registration-enabled false

$privateDnsZoneId = az network private-dns zone show --resource-group $resourceGroup --name $privateDnsZoneName --query id -o tsv

az network private-endpoint dns-zone-group create `
  --resource-group $resourceGroup `
  --endpoint-name $privateEndpointName `
  --name default `
  --private-dns-zone $privateDnsZoneId `
  --zone-name queue

if ($disablePublicNetworkAccess) {
  az storage account update --name $storageAccountName --resource-group $resourceGroup --public-network-access Disabled
}

$identity = az identity create --name $identityName --resource-group $resourceGroup --location $location -o json | ConvertFrom-Json
$acr = az acr show --name $acrName --resource-group $resourceGroup -o json | ConvertFrom-Json

az role assignment create `
  --assignee-object-id $identity.principalId `
  --assignee-principal-type ServicePrincipal `
  --role "Storage Queue Data Contributor" `
  --scope "$storageAccountId/queueServices/default/queues/$queueName"

az role assignment create `
  --assignee-object-id $identity.principalId `
  --assignee-principal-type ServicePrincipal `
  --role Reader `
  --scope $resourceGroupId

az role assignment create `
  --assignee-object-id $identity.principalId `
  --assignee-principal-type ServicePrincipal `
  --role AcrPull `
  --scope $acr.id

az acr config authentication-as-arm update --registry $acrName --status enabled

az acr build `
  --registry $acrName `
  --image $imageName `
  ./queue-app

az containerapp job create `
  --name $jobName `
  --resource-group $resourceGroup `
  --environment $containerAppsEnvironment `
  --workload-profile-name $workloadProfileName `
  --trigger-type Event `
  --replica-timeout $replicaTimeoutSeconds `
  --replica-retry-limit $replicaRetryLimit `
  --replica-completion-count 1 `
  --parallelism 1 `
  --min-executions 0 `
  --max-executions 1 `
  --polling-interval 60 `
  --scale-rule-name queue `
  --scale-rule-type azure-queue `
  --scale-rule-metadata "accountName=$storageAccountName" "queueName=$queueName" "queueLength=1" "queueLengthStrategy=visibleonly" `
  --scale-rule-identity $identity.id `
  --image "$($acr.loginServer)/$imageName" `
  --cpu 1.0 `
  --memory 2Gi `
  --registry-server $acr.loginServer `
  --registry-identity $identity.id `
  --mi-user-assigned $identity.id `
  --env-vars "AZURE_CLIENT_ID=$($identity.clientId)" "AZURE_SUBSCRIPTION_ID=$subscriptionId" "AZURE_STORAGE_ACCOUNT=$storageAccountName" "AZURE_STORAGE_QUEUE_NAME=$queueName" "REPLICA_TIMEOUT_SECONDS=$replicaTimeoutSeconds" "QUEUE_VISIBILITY_TIMEOUT_SECONDS=$visibilityTimeoutSeconds"

az containerapp job execution list --name $jobName --resource-group $resourceGroup -o table

