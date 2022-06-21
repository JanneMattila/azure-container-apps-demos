#!/usr/bin/env bash

cat >/etc/motd <<EOF
Azure Container Apps demo

GitHub: https://github.com/JanneMattila/azure-container-apps-demos
EOF

cat /etc/motd

# Run the main application
$@
