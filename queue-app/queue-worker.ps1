param(
    [string]$ScriptFile = "$PSScriptRoot/timer1.ps1"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$visibilityTimeoutSeconds = [int]$env:QUEUE_VISIBILITY_TIMEOUT_SECONDS
$replicaTimeoutSeconds = [int]$env:REPLICA_TIMEOUT_SECONDS
if ($replicaTimeoutSeconds -le 0 -or $visibilityTimeoutSeconds -le $replicaTimeoutSeconds -or $visibilityTimeoutSeconds -gt 604800) {
    throw "Queue visibility timeout must exceed the positive replica timeout and be at most seven days."
}

foreach ($variableName in @("AZURE_CLIENT_ID", "AZURE_SUBSCRIPTION_ID", "AZURE_STORAGE_ACCOUNT", "AZURE_STORAGE_QUEUE_NAME")) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variableName))) {
        throw "Missing environment variable: $variableName"
    }
}

if (-not (Test-Path -LiteralPath $ScriptFile -PathType Leaf)) {
    throw "Script not found: $ScriptFile"
}

Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity -AccountId $env:AZURE_CLIENT_ID -Subscription $env:AZURE_SUBSCRIPTION_ID | Out-Null

function Get-QueueHeaders {
    $accessToken = Get-AzAccessToken -ResourceUrl "https://storage.azure.com/"
    $token = $accessToken.Token
    if ($token -is [System.Security.SecureString]) {
        $token = [System.Net.NetworkCredential]::new("", $token).Password
    }

    @{
        Authorization = "Bearer $token"
        "x-ms-date" = [DateTime]::UtcNow.ToString("R")
        "x-ms-version" = "2023-11-03"
    }
}

$messagesUri = "https://$($env:AZURE_STORAGE_ACCOUNT).queue.core.windows.net/$($env:AZURE_STORAGE_QUEUE_NAME)/messages"
$webResponse = Invoke-WebRequest -Method Get -Uri "${messagesUri}?numofmessages=1&visibilitytimeout=$visibilityTimeoutSeconds" -Headers (Get-QueueHeaders) -TimeoutSec 60
$response = [System.Xml.XmlDocument]::new()
$response.Load($webResponse.RawContentStream)
$message = $response.SelectSingleNode("/QueueMessagesList/QueueMessage")
if ($null -eq $message) {
    Write-Output "No visible queue message; exiting."
    return
}

$env:QUEUE_MESSAGE_ID = $message.MessageId
$env:QUEUE_MESSAGE_TEXT = $message.MessageText
Write-Output "Processing message $($message.MessageId), dequeue count $($message.DequeueCount)."

& $ScriptFile
if (-not $?) {
    throw "Script failed; leaving the message in the queue."
}

$popReceipt = [Uri]::EscapeDataString($message.PopReceipt)
Invoke-RestMethod -Method Delete -Uri "$messagesUri/$($message.MessageId)?popreceipt=$popReceipt" -Headers (Get-QueueHeaders) -TimeoutSec 60 | Out-Null
Write-Output "Completed and deleted message $($message.MessageId)."