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
      "dm": {
        "enabled": true,
        "policy": "allowlist",
        "allowFrom": ${ALLOW_FROM}
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

# --- Write config file ---
cat > "${CONFIG_FILE}" <<EOF
{
  "agents": {
    "defaults": {
      "workspace": "${WORKSPACE_DIR}",
      "model": {
        "primary": "${OPENCLAW_MODEL:-openrouter/anthropic/claude-3.5-sonnet}"
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
      "enabled": true
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
    "level": "info",
    "consoleLevel": "info",
    "consoleStyle": "pretty"
  }
}
EOF

echo "[entrypoint] OpenClaw configuration written to ${CONFIG_FILE}"
echo "[entrypoint] Gateway token configured: yes"
echo "[entrypoint] Model: ${OPENCLAW_MODEL:-openrouter/anthropic/claude-3.5-sonnet}"
echo "[entrypoint] Persona: ${OPENCLAW_PERSONA_NAME:-Clawd}"
echo "[entrypoint] Workspace: ${WORKSPACE_DIR}"
echo "[entrypoint] Starting OpenClaw gateway..."

exec node dist/index.js gateway \
  --bind lan \
  --port "${GATEWAY_PORT:-18789}" \
  --allow-unconfigured \
  "$@"
