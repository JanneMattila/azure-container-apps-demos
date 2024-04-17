#!/usr/bin/env pwsh

Write-Output "Running Azure PowerShell based automation..."

# Use managed identity:
Connect-AzAccount -Identity -AccountId $env:AZURE_CLIENT_ID

if ($env:SCRIPT_FILE.Length -gt 0) {
    if ($env:SCRIPT_FILE.StartsWith("http")) {
        Write-Output "Running script file from web: $env:SCRIPT_FILE"
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString($env:SCRIPT_FILE))
    }
    else {
        Write-Output "Running script file from path: $env:SCRIPT_FILE"
        . $env:SCRIPT_FILE
    }
}
else {
    Write-Warning "No script file provided."
}
