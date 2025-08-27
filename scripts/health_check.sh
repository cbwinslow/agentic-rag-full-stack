#!/usr/bin/env bash
set -euo pipefail

# Simple health check script for services used in this stack. Exits non-zero if any
# required service returns non-OK.

INGEST_URL=${INGEST_URL:-http://localhost:8001/health}
NEXT_URL=${NEXT_URL:-http://localhost:3000/health}
SUPABASE_DB_HOST=${SUPABASE_DB_HOST:-localhost}
SUPABASE_DB_PORT=${SUPABASE_DB_PORT:-5432}

check_http(){
  url="$1"
  name="$2"
  status=$(curl -sS -o /dev/null -w "%{http_code}" "$url" || echo "000")
  if [ "$status" != "200" ]; then
    echo "FAIL: $name ($url) returned HTTP $status"
    return 1
  fi
  echo "OK: $name"
}

check_tcp(){
  host="$1"; port="$2"; name="$3"
  if ! timeout 1 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
    echo "FAIL: $name ($host:$port) not reachable"
    return 1
  fi
  echo "OK: $name"
}

ERR=0
check_http "$INGEST_URL" "ingest"
ERR=$((ERR + $?))
check_http "$NEXT_URL" "nextjs"
ERR=$((ERR + $?))
check_tcp "$SUPABASE_DB_HOST" "$SUPABASE_DB_PORT" "supabase-db"
ERR=$((ERR + $?))

if [ "$ERR" -ne 0 ]; then
  echo "One or more health checks failed"
  exit 2
fi

echo "All health checks OK"
