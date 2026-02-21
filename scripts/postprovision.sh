#!/usr/bin/env bash
set -euo pipefail

echo "=== OpenClaw: Post-Provision — Building container image ==="

if [ -z "${CONTAINER_REGISTRY_NAME:-}" ]; then
  echo "Error: CONTAINER_REGISTRY_NAME not set. Did provisioning succeed?"
  exit 1
fi

echo "Building image in ACR: ${CONTAINER_REGISTRY_NAME}..."
az acr build \
  --registry "${CONTAINER_REGISTRY_NAME}" \
  --image "openclaw:latest" \
  --file src/openclaw/Dockerfile \
  src/openclaw/

echo "=== Image built and pushed to ${CONTAINER_REGISTRY_NAME}.azurecr.io/openclaw:latest ==="
