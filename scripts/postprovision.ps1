#Requires -Version 7.0
$ErrorActionPreference = "Stop"

Write-Host "=== OpenClaw: Post-Provision — Building container image ===" -ForegroundColor Cyan

if (-not $env:CONTAINER_REGISTRY_NAME) {
    Write-Error "CONTAINER_REGISTRY_NAME not set. Did provisioning succeed?"
    exit 1
}

Write-Host "Building image in ACR: $env:CONTAINER_REGISTRY_NAME..."
az acr build `
    --registry $env:CONTAINER_REGISTRY_NAME `
    --image "openclaw:latest" `
    --file src/openclaw/Dockerfile `
    src/openclaw/

Write-Host "=== Image built and pushed to $env:CONTAINER_REGISTRY_NAME.azurecr.io/openclaw:latest ===" -ForegroundColor Green
