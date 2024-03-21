#!/usr/bin/env pwsh

$PSStyle.OutputRendering = "PlainText"

@"
Azure Container Apps demo

GitHub: https://github.com/JanneMattila/azure-container-apps-demos
"@ > /etc/motd

Get-Content /etc/motd

# Run the main application
. $args[0]
