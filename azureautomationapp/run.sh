#!/usr/bin/env bash

echo "Running az cli based automation..."

# Note: Due to this 
# https://github.com/Azure/azure-cli/issues/22677
# You cannot yet use this:
# az login --identity -u $AZURE_CLIENT_ID -o none
# az group list -o table

# Use manual method:
# Example from
# https://github.com/JanneMattila/hassio-addon-azuredns/blob/main/addon/run.sh
ACCESS_TOKEN=$(curl --no-progress-meter --silent "$IDENTITY_ENDPOINT?api-version=2019-08-01&client_id=$AZURE_CLIENT_ID&resource=https://management.azure.com/" -H "X-IDENTITY-HEADER: $IDENTITY_HEADER" | jq -r .access_token)
SUBSCRIPTIONS=$(curl --no-progress-meter --silent -H "Authorization: Bearer $ACCESS_TOKEN" "https://management.azure.com/subscriptions?api-version=2018-05-01")
echo $SUBSCRIPTIONS
