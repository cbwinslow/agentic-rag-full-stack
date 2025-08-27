#!/usr/bin/env bash
#!/bin/sh
set -euo pipefail

# Start the minimal supabase stack and initialize the DB
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.supabase.yml"

echo "Starting Supabase stack using $COMPOSE_FILE"
docker-compose -f "$COMPOSE_FILE" up -d

echo "Waiting for Postgres to accept connections..."
sleep 4

# Load envs from .env.local or .env.example
if [ -f "$ROOT_DIR/.env.local" ]; then
  export $(grep -v '^#' "$ROOT_DIR/.env.local" | xargs)
else
  export $(grep -v '^#' "$ROOT_DIR/.env.example" | xargs)
fi

if [ -z "${SUPABASE_DB_URL:-}" ]; then
  echo "SUPABASE_DB_URL is not set. Please set it in .env.local or .env.example"
  exit 1
fi

echo "Running DB initialization SQL"
psql "$SUPABASE_DB_URL" -f "$ROOT_DIR/supabase/init.sql"

echo "Supabase local stack started and initialized."
