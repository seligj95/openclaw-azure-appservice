# OpenClaw on Azure App Service

Deploy [OpenClaw](https://openclaw.ai) — your open-source personal AI assistant — to **Azure App Service (Web App for Containers)**. This sample uses the [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/) for one-command provisioning and deployment.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Resource Group: rg-{env}                                    │
│                                                              │
│  ┌──────────────┐   ┌──────────────────────────────────────┐ │
│  │  Azure        │   │  App Service (Web App for Containers)│ │
│  │  Container    │──▶│  - Linux container (Node.js 22)      │ │
│  │  Registry     │   │  - Port 18789                        │ │
│  │  (Basic)      │   │  - Always On + WebSockets            │ │
│  └──────────────┘   │  - Health Check at /health            │ │
│                      │  - System-assigned + User MI          │ │
│                      │  - Azure Files mount                  │ │
│                      └────────────┬─────────────────────────┘ │
│                                   │                           │
│  ┌──────────────┐   ┌────────────▼──────────┐                │
│  │  Log          │   │  Storage Account      │                │
│  │  Analytics    │   │  - Azure Files share  │                │
│  │  Workspace    │   │  - openclaw-workspace │                │
│  └──────────────┘   └───────────────────────┘                │
│                                                              │
│  ┌──────────────────────────────────────────────────┐        │
│  │  Azure Monitor Alerts (optional)                  │        │
│  │  - HTTP 5xx, health check, response time, volume  │        │
│  └──────────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────┘
```

**Communication channels:** Discord, Telegram (the bot listens for DMs and responds using the configured LLM).

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.60+)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) (v1.9+)
- An Azure subscription ([free trial](https://azure.microsoft.com/free/))
- An [OpenRouter](https://openrouter.ai/) API key (or another LLM provider supported by OpenClaw)
- A [Discord bot token](https://discord.com/developers/applications) and/or [Telegram bot token](https://core.telegram.org/bots#botfather)

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/YOUR_ORG/openclaw-azure-appservice.git
cd openclaw-azure-appservice
```

### 2. Log in to Azure

```bash
azd auth login
az login
```

### 3. Initialize and configure the environment

```bash
azd init -e dev
```

Set the required secrets and parameters:

```bash
# Required
azd env set OPENROUTER_API_KEY <your-openrouter-key>

# Discord (at least one channel required)
azd env set DISCORD_BOT_TOKEN <your-discord-bot-token>
azd env set DISCORD_ALLOWED_USERS <comma-separated-user-ids>

# Telegram (optional)
azd env set TELEGRAM_BOT_TOKEN <your-telegram-bot-token>
azd env set TELEGRAM_ALLOWED_USER_ID <your-telegram-user-id>

# Optional customization
azd env set OPENCLAW_MODEL "openrouter/anthropic/claude-3.5-sonnet"
azd env set OPENCLAW_PERSONA_NAME "Clawd"
```

### 4. Deploy

```bash
azd up
```

This single command will:
1. **Provision** all Azure infrastructure (App Service, ACR, Storage, Log Analytics)
2. **Build** the Docker image in ACR (via post-provision hook)
3. **Configure** the Web App to pull from ACR with managed identity
4. **Output** the URLs and next steps

### 5. Verify

```bash
# Check health endpoint
curl https://<your-app>.azurewebsites.net/health

# Stream live logs
az webapp log tail --name <webapp-name> --resource-group <rg-name>
```

## Configuration Reference

| Environment Variable | Required | Description |
|---|---|---|
| `OPENROUTER_API_KEY` | Yes | API key for LLM provider |
| `DISCORD_BOT_TOKEN` | Yes* | Discord bot token |
| `DISCORD_ALLOWED_USERS` | Yes* | Comma-separated Discord user IDs |
| `TELEGRAM_BOT_TOKEN` | No | Telegram bot token |
| `TELEGRAM_ALLOWED_USER_ID` | No | Telegram user ID for access control |
| `OPENCLAW_MODEL` | No | Model identifier (default: `openrouter/anthropic/claude-3.5-sonnet`) |
| `OPENCLAW_PERSONA_NAME` | No | Bot persona name (default: `Clawd`) |
| `OPENCLAW_GATEWAY_TOKEN` | No | Gateway auth token (auto-generated if empty) |

\* At least one channel (Discord or Telegram) must be configured.

### Infrastructure Parameters

| Parameter | Default | Description |
|---|---|---|
| `appServiceSkuName` | `P0v3` | App Service Plan SKU |
| `enableAlerts` | `true` | Enable Azure Monitor alerts |
| `alertEmailAddress` | `` | Email for alert notifications |
| `allowedIpRanges` | `` | Comma-separated CIDRs for IP restrictions |
| `imageTag` | `latest` | Container image tag |

## Persistent Storage

OpenClaw's workspace is mounted at `/mnt/openclaw-workspace` via Azure Files. This persists:
- Conversation history and session data
- Agent memory and context
- Downloaded files and artifacts

The file share (`openclaw-workspace`, 5 GB, Standard LRS) survives container restarts and redeployments.

## Monitoring

When `enableAlerts` is `true`, four alert rules are created:

| Alert | Condition | Severity |
|---|---|---|
| High HTTP 5xx Errors | > 10 errors in 5 minutes | Sev 1 (Error) |
| Health Check Degraded | < 80% health in 5 minutes | Sev 1 (Error) |
| High Response Time | > 30 seconds avg over 5 min | Sev 2 (Warning) |
| Unusual Request Volume | > 500 requests in 1 hour | Sev 3 (Informational) |

Logs flow to Log Analytics and include HTTP logs, console output, and platform diagnostics.

### Useful KQL Queries

```kql
// Recent errors
AppServiceHTTPLogs
| where ScStatus >= 500
| order by TimeGenerated desc
| take 20

// Container startup logs
AppServiceConsoleLogs
| where TimeGenerated > ago(1h)
| order by TimeGenerated asc

// Request latency percentiles
AppServiceHTTPLogs
| where TimeGenerated > ago(1h)
| summarize p50=percentile(TimeTaken, 50), p95=percentile(TimeTaken, 95), p99=percentile(TimeTaken, 99) by bin(TimeGenerated, 5m)
```

## Security

- **Managed Identity**: User-assigned MI for ACR pull (no admin credentials)
- **HTTPS Only**: HTTP traffic is automatically redirected
- **Minimum TLS 1.2**: Enforced at the platform level
- **FTP Disabled**: No FTP/FTPS access
- **IP Restrictions** (optional): Restrict access by CIDR blocks via `allowedIpRanges`
- **Secrets**: All API keys and tokens stored as App Settings (encrypted at rest)

## Updating OpenClaw

To update to the latest version of OpenClaw:

```bash
# Rebuild the container image (pulls latest from GitHub)
az acr build --registry <acr-name> --image openclaw:latest --file src/openclaw/Dockerfile src/openclaw/

# Restart the web app to pick up the new image
az webapp restart --name <webapp-name> --resource-group <rg-name>
```

Or re-run the full deployment:

```bash
azd up
```

## Cost Estimate

| Resource | SKU | Estimated Monthly Cost |
|---|---|---|
| App Service Plan | P0v3 | ~$74 |
| Container Registry | Basic | ~$5 |
| Storage Account | Standard LRS (5 GB) | ~$0.10 |
| Log Analytics | Pay-per-GB | ~$2–5 (low volume) |
| **Total** | | **~$81–84/month** |

> Costs vary by region. Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for precise estimates.

## App Service vs Container Apps

| Feature | App Service | Container Apps |
|---|---|---|
| **Best for** | Single-container web apps | Multi-container microservices |
| **Scaling** | Manual or auto-scale rules | KEDA-based event-driven scaling |
| **Always On** | ✅ Built-in (requires Basic+) | ✅ Min replicas = 1 |
| **WebSockets** | ✅ Native support | ✅ Native support |
| **Custom domains** | ✅ Simple UI/CLI | ✅ Supported |
| **SSH into container** | ✅ Built-in | ❌ Not available |
| **Deployment slots** | ✅ Staging slots | ✅ Revisions |
| **Azure Files mount** | ✅ Path mapping | ✅ Volume mount |
| **Pricing model** | Dedicated plan | Consumption or dedicated |

For OpenClaw (a single always-on container), **App Service** is a straightforward and cost-effective choice.

## Troubleshooting

### Container fails to start

```bash
# Check container logs
az webapp log tail --name <webapp-name> --resource-group <rg-name>

# Verify the image exists in ACR
az acr repository show-tags --name <acr-name> --repository openclaw
```

### Bot not responding to messages

1. Verify tokens are set: `azd env get-values | grep -i token`
2. Check the container logs for authentication errors
3. Ensure the bot is added to your Discord server / Telegram chat

### Health check failing

The health endpoint is at `/health` on port 18789. If it's failing:

```bash
# SSH into the container to debug
az webapp ssh --name <webapp-name> --resource-group <rg-name>

# Inside the container:
curl http://localhost:18789/health
```

## Cleanup

Remove all deployed resources:

```bash
azd down --purge --force
```

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT

## Related

- [OpenClaw](https://openclaw.ai) — The open-source personal AI assistant
- [OpenClaw on Container Apps](https://github.com/BandaruDheeraj/moltbot-azure-container-apps) — Alternative deployment using Azure Container Apps
- [Azure App Service Documentation](https://learn.microsoft.com/azure/app-service/)
