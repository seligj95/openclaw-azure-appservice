#Requires -Version 7.0

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  OpenClaw deployed to Azure App Service!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Web App:   $env:WEBAPP_URL"
Write-Host "  Gateway:   $env:WEBAPP_URL"
Write-Host "  Hostname:  $env:WEBAPP_HOSTNAME"
Write-Host ""
Write-Host "  Resource Group:  $env:AZURE_RESOURCE_GROUP"
Write-Host "  ACR:             $env:CONTAINER_REGISTRY_LOGIN_SERVER"
Write-Host ""
Write-Host "  To stream logs:"
Write-Host "    az webapp log tail --name $env:WEBAPP_NAME --resource-group $env:AZURE_RESOURCE_GROUP"
Write-Host ""
Write-Host "  To SSH into the container:"
Write-Host "    az webapp ssh --name $env:WEBAPP_NAME --resource-group $env:AZURE_RESOURCE_GROUP"
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
