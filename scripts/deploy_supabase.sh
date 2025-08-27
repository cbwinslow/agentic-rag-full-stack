#!/usr/bin/env bash
set -euo pipefail

# scripts/deploy_supabase.sh
# Minimal reproducible deploy helper for the polyanalysis Supabase compose stack.
# Usage:
#   ./scripts/deploy_supabase.sh         # build images and start the stack
#   ./scripts/deploy_supabase.sh --wipe-data  # also remove local DB data

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJ_ROOT/docker-compose.supabase.yml"
DB_DATA_DIR="$PROJ_ROOT/supabase/db"
IMAGE_NAME="polyanalysis/postgres-pgvector:15"

wipe_data=false
while [[ ${1:-} != "" ]]; do
  case "$1" in
    --wipe-data) wipe_data=true; shift ;;
    --help) echo "Usage: $0 [--wipe-data]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "Project root: $PROJ_ROOT"

if [ "$wipe_data" = true ]; then
  echo "Wiping DB data directory: $DB_DATA_DIR"
  rm -rf "$DB_DATA_DIR"
fi

# Ensure compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Compose file not found: $COMPOSE_FILE" >&2
  exit 2
fi

# Build custom Postgres image with pgvector
echo "Building $IMAGE_NAME (this may take a while)"
docker build -t "$IMAGE_NAME" "$PROJ_ROOT/supabase/postgres-pgvector"

# Pull pinned Supabase images (so compose doesn't block on network interruptions)
echo "Pulling required Supabase images"
docker pull ghcr.io/supabase/gotrue:v2.178.0 || true
docker pull postgrest/postgrest:v13.0.5 || true
docker pull ghcr.io/supabase/realtime:v2.43.1 || true
docker pull ghcr.io/supabase/storage-api:v1.26.4 || true
docker pull ghcr.io/supabase/studio:2025.08.25-sha-72a94af || true

# Bring up the stack
echo "Starting compose stack"
docker-compose -f "$COMPOSE_FILE" up -d --build

echo "Done. Use 'docker-compose -f $COMPOSE_FILE logs -f' to tail logs."