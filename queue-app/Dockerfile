FROM mcr.microsoft.com/azure-powershell:latest

WORKDIR /app
COPY queue-worker.ps1 timer1.ps1 ./

ENTRYPOINT ["pwsh", "-NoLogo", "-NoProfile", "-File", "/app/queue-worker.ps1"]