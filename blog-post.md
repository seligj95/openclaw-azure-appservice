# How to Host OpenClaw on Azure App Service

*Your personal AI assistant, running 24/7 in the cloud — no laptop required.*

---

OpenClaw is an open-source personal AI assistant that runs as a persistent service, connecting to your Discord, Telegram, and other channels. Most people run it on their local machine, but what if you want it available all the time — even when your laptop is closed?

Dheeraj Bandaru wrote a great post on [hosting OpenClaw on Azure Container Apps](https://www.agent-lair.com/deploy-clawdbot-azure-container-apps), which inspired this guide. As Dheeraj put it:

> "Most guides show AWS EC2 or VPS hosting. I wanted to see if Azure Container Apps could do it easier!"

This post takes a similar approach but uses **Azure App Service (Web App for Containers)** instead — a natural fit if you're already familiar with App Service or prefer its operational model. Both are excellent options; pick the one that matches your team's experience.

## Why Host OpenClaw in the Cloud?

Running OpenClaw locally works, but it has limitations:

- **Uptime** — your bot stops when your computer sleeps or restarts
- **Network** — your home connection may be unreliable or behind NAT
- **Resources** — your machine is doing double duty as both your workstation and a server

Moving to Azure means OpenClaw runs 24/7 on dedicated infrastructure, accessible from anywhere.

## Why Azure App Service?

There are several ways to run containers on Azure — Container Apps, AKS, Container Instances, and App Service. [Dheeraj's Container Apps guide](https://www.agent-lair.com/deploy-clawdbot-azure-container-apps) is a great option, especially if you want event-driven scaling or plan to add sidecars later. App Service is another strong choice, particularly if:

1. **You already know App Service** — same platform you use for web apps and APIs
2. **Always On is built in** — no need to configure minimum replicas
3. **WebSocket support** — OpenClaw's gateway uses WebSockets for real-time communication
4. **SSH access** — you can SSH directly into your running container from the Azure Portal or CLI
5. **Deployment slots** — test updates in staging before swapping to production
6. **Azure Files integration** — persistent storage that survives container restarts
7. **Cost predictability** — a fixed monthly plan with no per-request surprises

### Choosing Between App Service and Container Apps

Both services run containers well. Here's a quick comparison to help you decide:

| Consideration | App Service | Container Apps |
|---|---|---|
| Container model | Single container | Multi-container, sidecars |
| Scaling | Auto-scale rules | KEDA event-driven |
| Always On | Built-in | Min replicas = 1 |
| In-container SSH | ✅ Yes | ❌ No |
| Deployment slots | ✅ Yes | Revisions |
| Best for | Web apps, APIs, bots | Microservices, event processing |

For a single always-on container like OpenClaw, either service works. This guide uses App Service; if you'd prefer Container Apps, check out [Dheeraj's guide](https://www.agent-lair.com/deploy-clawdbot-azure-container-apps).

## Architecture Overview

Here's what gets deployed:

```
┌──────────────────────────────────────────────────────────┐
│  Resource Group                                          │
│                                                          │
│  ┌─────────────┐    ┌────────────────────────────┐       │
│  │ Azure        │    │ App Service                │       │
│  │ Container    │───▶│ (Web App for Containers)   │       │
│  │ Registry     │    │                            │       │
│  └─────────────┘    │  OpenClaw container         │       │
│                      │  Port 18789                 │       │
│                      │  WebSockets enabled         │       │
│                      │  Health checks at /health   │       │
│                      └──┬───────────┬─────────────┘       │
│                         │           │                     │
│  ┌─────────────┐   ┌────▼─────┐  ┌──▼──────────────────┐  │
│  │ Log          │   │ Azure    │  │ Azure OpenAI        │  │
│  │ Analytics    │   │ Files    │  │ (GPT-4o)            │  │
│  └─────────────┘   └──────────┘  └─────────────────────┘  │
└──────────────────────────────────────────────────────────┘

        ▲                    ▲
        │                    │
   Discord Bot          Telegram Bot
   (DMs)                (DMs)
```

Key design decisions:

- **Azure Container Registry** stores the OpenClaw Docker image (built from source)
- **Managed Identity** pulls images from ACR — no passwords stored in config
- **Azure OpenAI** provisions GPT-4o automatically — no external API keys needed
- **Azure Files** mounts at `/mnt/openclaw-workspace` for conversation history and agent memory
- **Log Analytics** captures HTTP logs, console output, and platform diagnostics
- **Azure Monitor alerts** notify you if something goes wrong (5xx errors, health check failures, etc.)

## Why Azure OpenAI?

Most OpenClaw users get their LLM by signing up for a third-party API key — Anthropic, OpenAI, OpenRouter, or similar. That works, but it means managing a separate account, billing relationship, and API key outside of your Azure environment.

This template provisions **Azure OpenAI (GPT-4o)** alongside the bot as part of the same `azd up` deployment. That gives you:

- **One bill** — LLM usage appears on your existing Azure invoice alongside compute, storage, and networking. No separate API account to manage.
- **Data stays in Azure** — your prompts and completions travel between Azure services within the Microsoft network, not to a third-party endpoint.
- **Enterprise controls** — Azure RBAC, Private Endpoints, content filtering, and audit logging are all available if you need them.
- **No external API key signup** — `azd up` provisions the model and injects the key into the App Service automatically.

If you already have an Anthropic or OpenRouter key you prefer, you can set `enableAzureOpenAi` to `false` and configure your own provider in the entrypoint — the template is flexible. But for an all-in-one Azure deployment, Azure OpenAI keeps everything under one roof.

## Step-by-Step Deployment

### Prerequisites

You'll need:
- An Azure subscription
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- A Discord bot token (and/or Telegram bot token)

> Azure OpenAI (GPT-4o) is provisioned automatically — no external API key needed.

### 1. Clone and Configure

```bash
git clone https://github.com/seligj95/openclaw-azure-appservice.git
cd openclaw-azure-appservice

azd auth login
az login

azd init -e my-openclaw
```

### 2. Set Your Secrets

```bash
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
1. `azd provision` — creates all Azure resources via Bicep templates (including Azure OpenAI)
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
- **Secrets as App Settings** — encrypted at rest by the platform

### Do I Need to Lock Down the App Service URL?

Short answer: probably not, but it depends on your comfort level.

**What's exposed on the public URL:**
- `/health` — returns a 200 status, no sensitive data
- **Control UI** — a web dashboard for managing your bot (if `controlUi.enabled` is set to `true`)
- **Gateway WebSocket** — requires the gateway token to authenticate; unauthenticated connections are rejected

**What's NOT exposed:**
Discord and Telegram traffic never flows through the App Service URL. The bot makes *outbound* connections to Discord/Telegram APIs using your bot tokens. Users interact via those platforms, not by hitting the App Service endpoint.

The gateway token already protects the WebSocket endpoint. The main exposure is the Control UI — anyone who finds your URL could access it.

### Options (lightest to heaviest)

1. **Disable the Control UI** — set `controlUi.enabled: false` in the config. You'd manage everything via Discord DMs and logs. Simplest approach if you don't need the dashboard.

2. **IP access restrictions** — lock the App Service to your IP or VPN CIDR. Discord/Telegram still work because the bot connects outbound. The Bicep template includes an optional `allowedIpRanges` parameter for this:

   ```bash
   azd env set allowedIpRanges "203.0.113.42/32"
   azd up
   ```

3. **Easy Auth (Entra ID)** — adds a login page in front of the entire app. Useful if you want to share the Control UI with a team, but overkill for a personal bot.

For most personal deployments, **IP restrictions** are the sweet spot — one parameter, no code changes, and the Control UI stays usable.

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

Running this setup costs approximately **$85–90/month** on the P0v4 plan (plus Azure OpenAI usage):

| Resource | Monthly |
|---|---|
| App Service (P0v4) | ~$77 |
| Container Registry (Basic) | ~$5 |
| Azure OpenAI (GPT-4o) | Pay-per-token |
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

If you're currently running OpenClaw on your laptop and want it running 24/7, give this a try. Big thanks to [Dheeraj Bandaru](https://github.com/BandaruDheeraj) for the original [Container Apps deployment](https://www.agent-lair.com/deploy-clawdbot-azure-container-apps) that this project builds on — if Container Apps is more your style, start there.

---

*Have questions or run into issues? Open an issue on the [GitHub repo](https://github.com/seligj95/openclaw-azure-appservice) or reach out on [openclaw.ai](https://openclaw.ai).*
