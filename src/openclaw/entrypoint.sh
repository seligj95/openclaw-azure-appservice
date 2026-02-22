#!/bin/bash
set -e

# ============================================================
# OpenClaw Azure App Service Entrypoint
# Generates openclaw.json config from environment variables
# ============================================================

CONFIG_DIR="${HOME}/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE:-/mnt/openclaw-workspace}"

mkdir -p "${CONFIG_DIR}" "${WORKSPACE_DIR}"

# --- Generate gateway token if not provided ---
if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ]; then
  OPENCLAW_GATEWAY_TOKEN=$(head -c 32 /dev/urandom | xxd -p | head -c 32)
  echo "[entrypoint] Generated gateway token (no OPENCLAW_GATEWAY_TOKEN set)"
fi

# --- Build Discord channel config ---
DISCORD_CONFIG=""
if [ -n "${DISCORD_BOT_TOKEN}" ]; then
  # Build allowFrom array from comma-separated DISCORD_ALLOWED_USERS
  ALLOW_FROM="[]"
  if [ -n "${DISCORD_ALLOWED_USERS}" ]; then
    ALLOW_FROM=$(echo "${DISCORD_ALLOWED_USERS}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
    ALLOW_FROM="[${ALLOW_FROM}]"
  fi

  DISCORD_CONFIG=$(cat <<DISCORD
    "discord": {
      "enabled": true,
      "token": "${DISCORD_BOT_TOKEN}",
      "dmPolicy": "allowlist",
      "allowFrom": ${ALLOW_FROM},
      "dm": {
        "enabled": true
      },
      "groupPolicy": "open"
    }
DISCORD
  )
  echo "[entrypoint] Discord channel configured: yes (DM allowlist: ${DISCORD_ALLOWED_USERS:-none})"
else
  echo "[entrypoint] Discord channel configured: no (DISCORD_BOT_TOKEN not set)"
fi

# --- Build Telegram channel config ---
TELEGRAM_CONFIG=""
if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
  TELEGRAM_ALLOWED=""
  if [ -n "${TELEGRAM_ALLOWED_USER_ID}" ]; then
    TELEGRAM_ALLOWED=$(echo "${TELEGRAM_ALLOWED_USER_ID}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
    TELEGRAM_ALLOWED="[${TELEGRAM_ALLOWED}]"
  else
    TELEGRAM_ALLOWED="[]"
  fi

  TELEGRAM_CONFIG=$(cat <<TELEGRAM
    "telegram": {
      "enabled": true,
      "token": "${TELEGRAM_BOT_TOKEN}",
      "allowedUsers": ${TELEGRAM_ALLOWED}
    }
TELEGRAM
  )
  echo "[entrypoint] Telegram channel configured: yes"
else
  echo "[entrypoint] Telegram channel configured: no (TELEGRAM_BOT_TOKEN not set)"
fi

# --- Combine channel configs ---
CHANNELS_INNER=""
if [ -n "${DISCORD_CONFIG}" ] && [ -n "${TELEGRAM_CONFIG}" ]; then
  CHANNELS_INNER="${DISCORD_CONFIG},
${TELEGRAM_CONFIG}"
elif [ -n "${DISCORD_CONFIG}" ]; then
  CHANNELS_INNER="${DISCORD_CONFIG}"
elif [ -n "${TELEGRAM_CONFIG}" ]; then
  CHANNELS_INNER="${TELEGRAM_CONFIG}"
fi

# --- Build Azure OpenAI provider config ---
MODELS_CONFIG=""
if [ -n "${AZURE_OPENAI_ENDPOINT}" ] && [ -n "${AZURE_OPENAI_API_KEY}" ]; then
  DEPLOYMENT="${AZURE_OPENAI_DEPLOYMENT_NAME:-gpt-4o}"
  # Use the OpenAI-compatible /openai/v1 path (no ?api-version= query param needed).
  # The standard OpenAI SDK constructs URLs via string concatenation (baseURL + "/chat/completions"),
  # so query params in baseUrl break URL construction and cause 404 errors.
  AOAI_BASE_URL="${AZURE_OPENAI_ENDPOINT%/}/openai/v1"
  MODELS_CONFIG=$(cat <<MODELS
  "models": {
    "mode": "merge",
    "providers": {
      "azure-openai": {
        "baseUrl": "${AOAI_BASE_URL}",
        "apiKey": "${AZURE_OPENAI_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "${DEPLOYMENT}",
            "name": "${DEPLOYMENT} (Azure OpenAI)",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 128000,
            "maxTokens": 16384
          }
        ]
      }
    }
  },
MODELS
  )
  # Override the default model to use Azure OpenAI
  OPENCLAW_MODEL="azure-openai/${DEPLOYMENT}"
  echo "[entrypoint] Azure OpenAI configured: endpoint=${AZURE_OPENAI_ENDPOINT} deployment=${DEPLOYMENT}"
else
  echo "[entrypoint] Azure OpenAI not configured (AZURE_OPENAI_ENDPOINT not set)"
fi

# --- Write config file ---
cat > "${CONFIG_FILE}" <<EOF
{
${MODELS_CONFIG}
  "agents": {
    "defaults": {
      "workspace": "${WORKSPACE_DIR}",
      "model": {
        "primary": "${OPENCLAW_MODEL}"
      }
    },
    "list": [
      {
        "id": "main",
        "identity": {
          "name": "${OPENCLAW_PERSONA_NAME:-Clawd}",
          "theme": "helpful assistant",
          "emoji": "🦞"
        }
      }
    ]
  },
  "channels": {
${CHANNELS_INNER}
  },
  "gateway": {
    "port": ${GATEWAY_PORT:-18789},
    "bind": "lan",
    "controlUi": {
      "enabled": true,
      "dangerouslyDisableDeviceAuth": true
    },
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    }
  },
  "session": {
    "dmScope": "main",
    "reset": {
      "mode": "daily",
      "atHour": 4
    }
  },
  "logging": {
    "level": "debug",
    "consoleLevel": "debug",
    "consoleStyle": "pretty"
  }
}
EOF

echo "[entrypoint] OpenClaw configuration written to ${CONFIG_FILE}"
echo "[entrypoint] Gateway token configured: yes"
echo "[entrypoint] Model: ${OPENCLAW_MODEL}"
echo "[entrypoint] Persona: ${OPENCLAW_PERSONA_NAME:-Clawd}"
echo "[entrypoint] Workspace: ${WORKSPACE_DIR}"
echo "[entrypoint] Starting OpenClaw gateway..."

# Dump config and tail file log after Doctor modifies it
(
  sleep 30
  echo "[entrypoint-debug] === CONFIG AFTER DOCTOR (30s delay) ==="
  cat "${CONFIG_FILE}" 2>/dev/null || echo "[entrypoint-debug] config file not found"
  echo "[entrypoint-debug] === END CONFIG ==="
  # Tail the file log so verbose/debug messages appear in stdout
  LOG_FILE=$(ls -t /tmp/openclaw/openclaw*.log 2>/dev/null | head -1)
  if [ -n "${LOG_FILE}" ]; then
    echo "[entrypoint-debug] Tailing log file: ${LOG_FILE}"
    tail -f "${LOG_FILE}" &
  fi
) &

exec node dist/index.js gateway \
  --verbose \
  --bind lan \
  --port "${GATEWAY_PORT:-18789}" \
  --allow-unconfigured \
  "$@"
