#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_NAME="local-postgres-pgvector:15"
CONTAINER_NAME="polyanalysis_pgvector"
PORT=${1:-55432}
PW=${2:-postgres}

echo "Building image $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" -f "$ROOT_DIR/supabase/postgres-pgvector/Dockerfile" "$ROOT_DIR"

echo "Stopping any existing container..."
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "Running container on port $PORT"
docker run -d --name "$CONTAINER_NAME" -e POSTGRES_PASSWORD="$PW" -e POSTGRES_USER=postgres -e POSTGRES_DB=graphrag -p ${PORT}:5432 "$IMAGE_NAME"

echo "Container started: $CONTAINER_NAME (port $PORT)"
