#!/usr/bin/env pwsh

Write-Output "Running Azure PowerShell based automation..."

# Use managed identity:
Connect-AzAccount -Identity -AccountId $env:AZURE_CLIENT_ID

if ($env:SCRIPT_FILE.Length -gt 0) {
    Write-Output "Running script file: $env:SCRIPT_FILE"
    . $env:SCRIPT_FILE
}
else {
    Write-Output "No script file provided. Running default action..."
    Get-AzResourceGroup
}
