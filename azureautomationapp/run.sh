#!/usr/bin/env bash

echo "Running az cli based automation..."

# Your logic here
az login --identity -o none
az group list -o table
