FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    socat curl git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone and build OpenClaw from source
ARG OPENCLAW_VERSION=main
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} https://github.com/openclaw/openclaw.git .

RUN corepack enable
RUN pnpm install --frozen-lockfile
RUN pnpm build
RUN pnpm ui:install
RUN pnpm ui:build

# Create directories for config and workspace
RUN mkdir -p /home/node/.openclaw /home/node/claw

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV NODE_ENV=production
ENV GATEWAY_PORT=18789
ENV GATEWAY_BIND=0.0.0.0
ENV HOME=/home/node
ENV XDG_CONFIG_HOME=/home/node/.openclaw
ENV TERM=xterm-256color

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:18789/health || exit 1

EXPOSE 18789

ENTRYPOINT ["/app/entrypoint.sh"]
