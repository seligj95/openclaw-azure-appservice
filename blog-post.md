# How to Host OpenClaw on Azure App Service

*Your personal AI assistant, running 24/7 in the cloud — no laptop required.*

---

OpenClaw is an open-source personal AI assistant that runs as a persistent service, connecting to your Discord, Telegram, and other channels. Most people run it on their local machine, but what if you want it available all the time — even when your laptop is closed?

In this post, I'll walk you through deploying OpenClaw to **Azure App Service** using Web App for Containers. We'll cover why App Service is a great fit, how the infrastructure works, and how to get it running with a single command.

## Why Host OpenClaw in the Cloud?

Running OpenClaw locally works, but it has limitations:

- **Uptime** — your bot stops when your computer sleeps or restarts
- **Network** — your home connection may be unreliable or behind NAT
- **Resources** — your machine is doing double duty as both your workstation and a server

Moving to Azure means OpenClaw runs 24/7 on dedicated infrastructure, accessible from anywhere.

## Why Azure App Service?

There are many ways to run containers on Azure — Container Apps, AKS, Container Instances, and more. For OpenClaw, **App Service (Web App for Containers)** stands out because:

1. **Simplicity** — it's a single always-on container; App Service is purpose-built for this
2. **Always On** — no cold starts, no scale-to-zero surprises
3. **WebSocket support** — OpenClaw's gateway uses WebSockets for real-time communication
4. **SSH access** — you can SSH directly into your running container from the Azure Portal or CLI
5. **Deployment slots** — test updates in staging before swapping to production
6. **Azure Files integration** — persistent storage that survives container restarts
7. **Cost predictability** — a fixed monthly plan with no per-request surprises

### App Service vs Container Apps

| Consideration | App Service | Container Apps |
|---|---|---|
| Container model | Single container | Multi-container, sidecars |
| Scaling | Auto-scale rules | KEDA event-driven |
| Always On | Built-in | Min replicas = 1 |
| In-container SSH | ✅ Yes | ❌ No |
| Deployment slots | ✅ Yes | Revisions |
| Best for | Web apps, APIs, bots | Microservices, event processing |

For a single-container bot like OpenClaw, App Service gives you everything you need without the complexity of a container orchestration platform.

## Architecture Overview

Here's what gets deployed:

```
┌─────────────────────────────────────────────────────┐
│  Resource Group                                     │
│                                                     │
│  ┌─────────────┐    ┌────────────────────────────┐  │
│  │ Azure        │    │ App Service                │  │
│  │ Container    │───▶│ (Web App for Containers)   │  │
│  │ Registry     │    │                            │  │
│  └─────────────┘    │  OpenClaw container         │  │
│                      │  Port 18789                 │  │
│                      │  WebSockets enabled         │  │
│                      │  Health checks at /health   │  │
│                      └──────────┬─────────────────┘  │
│                                 │                    │
│  ┌─────────────┐    ┌──────────▼──────────┐         │
│  │ Log          │    │ Azure Files         │         │
│  │ Analytics    │    │ Persistent storage  │         │
│  └─────────────┘    └─────────────────────┘         │
└─────────────────────────────────────────────────────┘

        ▲                    ▲
        │                    │
   Discord Bot          Telegram Bot
   (DMs)                (DMs)
```

Key design decisions:

- **Azure Container Registry** stores the OpenClaw Docker image (built from source)
- **Managed Identity** pulls images from ACR — no passwords stored in config
- **Azure Files** mounts at `/mnt/openclaw-workspace` for conversation history and agent memory
- **Log Analytics** captures HTTP logs, console output, and platform diagnostics
- **Azure Monitor alerts** notify you if something goes wrong (5xx errors, health check failures, etc.)

## Step-by-Step Deployment

### Prerequisites

You'll need:
- An Azure subscription
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- An [OpenRouter API key](https://openrouter.ai/) for LLM access
- A Discord bot token (and/or Telegram bot token)

### 1. Clone and Configure

```bash
git clone https://github.com/YOUR_ORG/openclaw-azure-appservice.git
cd openclaw-azure-appservice

azd auth login
az login

azd init -e my-openclaw
```

### 2. Set Your Secrets

```bash
# LLM provider
azd env set OPENROUTER_API_KEY "sk-or-..."

# Discord
azd env set DISCORD_BOT_TOKEN "your-discord-bot-token"
azd env set DISCORD_ALLOWED_USERS "123456789,987654321"

# Telegram (optional)
azd env set TELEGRAM_BOT_TOKEN "your-telegram-bot-token"
azd env set TELEGRAM_ALLOWED_USER_ID "your-user-id"
```

### 3. Deploy Everything

```bash
azd up
```

That's it. One command provisions the infrastructure, builds the container image in ACR, deploys it to App Service, and prints the URL.

Behind the scenes, `azd up` runs:
1. `azd provision` — creates all Azure resources via Bicep templates
2. Post-provision hook — builds the Docker image using `az acr build`
3. `azd deploy` — (no-op for infra-only, but triggers the post-deploy output hook)

### 4. Verify It's Running

```bash
# Health check
curl https://app-xxxxx.azurewebsites.net/health

# Stream logs
az webapp log tail --name app-xxxxx --resource-group rg-my-openclaw
```

Send a DM to your bot on Discord or Telegram — it should respond!

## How the Container Works

The Dockerfile builds OpenClaw from source:

```dockerfile
FROM node:22-bookworm
# Clone, install deps, build
RUN git clone https://github.com/openclaw/openclaw.git ...
RUN pnpm install && pnpm build
```

At startup, the `entrypoint.sh` script:
1. Reads environment variables (tokens, API keys, model config)
2. Generates `~/.openclaw/openclaw.json` with the correct channel and gateway configuration
3. Starts OpenClaw in gateway mode on port 18789

This means you configure everything through App Service's **Application Settings** — no need to SSH in and edit config files.

## Persistent Storage with Azure Files

One concern with containerized deployments is data persistence. When a container restarts, everything in its filesystem is lost.

OpenClaw solves this with an Azure Files mount:

```
Storage Account → File Share (openclaw-workspace) → Mounted at /mnt/openclaw-workspace
```

This share persists:
- Conversation history
- Agent memory and context
- Downloaded files and artifacts

Even if the container restarts, your bot picks up right where it left off.

## Monitoring and Alerts

The deployment includes optional Azure Monitor alerts:

- **HTTP 5xx errors** > 10 in 5 minutes → email notification
- **Health check** drops below 80% → email notification
- **Response time** exceeds 30 seconds → warning
- **Unusual volume** > 500 requests per hour → informational

All logs flow to Log Analytics. Some useful KQL queries:

```kql
// What happened in the last hour?
AppServiceConsoleLogs
| where TimeGenerated > ago(1h)
| order by TimeGenerated asc

// Any errors?
AppServiceHTTPLogs
| where ScStatus >= 500
| order by TimeGenerated desc
```

## Security

The deployment follows Azure security best practices:

- **No passwords for ACR** — managed identity with AcrPull role
- **HTTPS only** — HTTP redirects automatically
- **TLS 1.2 minimum**
- **FTP disabled**
- **Optional IP restrictions** — lock down access to specific CIDRs
- **Secrets as App Settings** — encrypted at rest by the platform

## What About Channels That Need Local Access?

OpenClaw supports many channels. Here's what works in the cloud vs. what needs a local machine:

| Channel | Cloud-Ready? | Notes |
|---|---|---|
| Discord | ✅ Yes | Bot token connects via API |
| Telegram | ✅ Yes | Bot token connects via API |
| Email | ✅ Yes | Uses SMTP/API |
| Calendar | ✅ Yes | Uses API integration |
| GitHub | ✅ Yes | Uses GitHub API |
| Web browsing | ✅ Yes | Headless browser in container |
| iMessage | ❌ No | Requires macOS |
| WhatsApp | ⚠️ Limited | Requires QR code scan, headless limitations |

For channels that need local access, you can run a second OpenClaw instance locally that handles just those channels.

## Cost

Running this setup costs approximately **$81–84/month** on the P0v3 plan:

| Resource | Monthly |
|---|---|
| App Service (P0v3) | ~$74 |
| Container Registry (Basic) | ~$5 |
| Storage (5 GB Standard) | ~$0.10 |
| Log Analytics | ~$2–5 |

That's less than many cloud VMs, and you get managed TLS, health checks, deployment slots, and monitoring included.

## Updating OpenClaw

When a new version of OpenClaw is released:

```bash
# Rebuild the image (pulls latest source)
az acr build --registry <acr-name> --image openclaw:latest \
  --file src/openclaw/Dockerfile src/openclaw/

# Restart to pick up the new image
az webapp restart --name <webapp-name> --resource-group <rg-name>
```

Or just run `azd up` again.

## Cleanup

To remove everything:

```bash
azd down --purge --force
```

## Wrapping Up

Azure App Service is an excellent fit for hosting OpenClaw:

- **One command** (`azd up`) to go from zero to a running bot
- **Always on** with WebSocket support and health checks
- **Persistent storage** via Azure Files
- **Secure by default** with managed identity and HTTPS
- **Observable** with Log Analytics and Azure Monitor alerts
- **Simple to update** — rebuild the image and restart

If you're currently running OpenClaw on your laptop and want it running 24/7, give this a try. And if you prefer Kubernetes-style container orchestration, check out the [Container Apps deployment](https://github.com/BandaruDheeraj/moltbot-azure-container-apps) as an alternative.

---

*Have questions or run into issues? Open an issue on the [GitHub repo](https://github.com/YOUR_ORG/openclaw-azure-appservice) or reach out on [openclaw.ai](https://openclaw.ai).*
