#!/usr/bin/env pwsh

Write-Output "Running Azure PowerShell based automation..."

# Use managed identity:
Connect-AzAccount -Identity -AccountId $env:AZURE_CLIENT_ID
Get-AzResourceGroup
