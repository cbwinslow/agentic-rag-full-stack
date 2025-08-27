#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker/docker-compose.stack.yml"

echo "Starting full local stack via $COMPOSE_FILE"
docker compose -f "$COMPOSE_FILE" --env-file .env up -d
