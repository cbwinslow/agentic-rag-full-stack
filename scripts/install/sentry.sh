#!/usr/bin/env bash
set -euo pipefail

# scripts/install/sentry.sh
# Install Sentry for error tracking and performance monitoring
# Supports both Docker and bare metal installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
SENTRY_VERSION="${SENTRY_VERSION:-24.1.0}"
SENTRY_PORT="${SENTRY_PORT:-9000}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
SENTRY_DATA_DIR="${PROJECT_ROOT}/data/sentry"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--port PORT] [--data-dir DIR]"
    echo "  --docker       Install using Docker (default)"
    echo "  --bare-metal   Install directly on host system"
    echo "  --port PORT    Set Sentry port (default: 9000)"
    echo "  --data-dir     Set data directory (default: ./data/sentry)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --port) SENTRY_PORT="$2"; shift 2 ;;
        --data-dir) SENTRY_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing Sentry error tracking platform..."
echo "Installation type: $INSTALL_TYPE"
echo "Port: $SENTRY_PORT"
echo "Data directory: $SENTRY_DATA_DIR"

# Create data directory
mkdir -p "$SENTRY_DATA_DIR"

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing Sentry using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Clone Sentry self-hosted repository
    if [ ! -d "$SENTRY_DATA_DIR/self-hosted" ]; then
        echo "Cloning Sentry self-hosted repository..."
        git clone https://github.com/getsentry/self-hosted.git "$SENTRY_DATA_DIR/self-hosted"
    fi
    
    cd "$SENTRY_DATA_DIR/self-hosted"
    
    # Create environment configuration
    cat > .env.custom <<EOF
SENTRY_WEB_PORT=${SENTRY_PORT}
SENTRY_SECRET_KEY=$(openssl rand -hex 32)
COMPOSE_PROJECT_NAME=sentry
SENTRY_IMAGE=getsentry/sentry:${SENTRY_VERSION}
SNUBA_IMAGE=getsentry/snuba:${SENTRY_VERSION}
RELAY_IMAGE=getsentry/relay:${SENTRY_VERSION}
SYMBOLICATOR_IMAGE=getsentry/symbolicator:${SENTRY_VERSION}
VROOM_IMAGE=getsentry/vroom:${SENTRY_VERSION}
WAL2JSON_VERSION=2.5
CLICKHOUSE_VERSION=22.3.15.33-alpine
REDIS_VERSION=6.2.14-alpine
POSTGRES_VERSION=14.9-alpine
EOF
    
    # Run installation script
    echo "Running Sentry installation script..."
    ./install.sh --skip-user-creation --no-report-self-hosted-issues
    
    # Create docker-compose override for custom port
    cat > docker-compose.override.yml <<EOF
version: '3.4'
services:
  web:
    ports:
      - "${SENTRY_PORT}:9000"
  nginx:
    ports:
      - "${SENTRY_PORT}:80"
EOF
    
    echo "Starting Sentry containers..."
    docker compose up -d
    
    echo "Waiting for Sentry to be ready..."
    sleep 30
    
    # Wait for Sentry to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$SENTRY_PORT/_health/" &>/dev/null; then
            echo "Sentry is ready!"
            break
        fi
        echo "Waiting for Sentry... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: Sentry failed to start within expected time"
        exit 1
    fi
    
    # Create initial user
    echo "Creating Sentry admin user..."
    docker compose exec -T web sentry createuser --email admin@example.com --password admin --superuser --no-input || true
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Installing Sentry on bare metal..."
    
    # Check if Python is available
    if ! command -v python3 &> /dev/null; then
        echo "Error: Python 3 is not installed. Please install Python 3."
        exit 1
    fi
    
    # Create virtual environment
    python3 -m venv "$SENTRY_DATA_DIR/venv"
    source "$SENTRY_DATA_DIR/venv/bin/activate"
    
    # Install Sentry
    pip install --upgrade pip
    pip install sentry[postgres]==24.1.0
    
    # Create configuration directory
    mkdir -p "$SENTRY_DATA_DIR/config"
    
    # Generate configuration
    cd "$SENTRY_DATA_DIR"
    sentry init "$SENTRY_DATA_DIR/config"
    
    # Update configuration
    cat > "$SENTRY_DATA_DIR/config/sentry.conf.py" <<EOF
import os
from sentry.conf.server import *

DATABASES = {
    'default': {
        'ENGINE': 'sentry.db.postgres',
        'NAME': 'sentry',
        'USER': 'sentry',
        'PASSWORD': 'sentry',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}

SENTRY_CACHE = 'sentry.cache.redis.RedisCache'

BROKER_URL = 'redis://localhost:6379'

SENTRY_RATELIMITER = 'sentry.ratelimits.redis.RedisRateLimiter'

SENTRY_BUFFER = 'sentry.buffer.redis.RedisBuffer'

SENTRY_QUOTAS = 'sentry.quotas.redis.RedisQuota'

SENTRY_TSDB = 'sentry.tsdb.redis.RedisTSDB'

SENTRY_DIGESTS = 'sentry.digests.backends.redis.RedisBackend'

SENTRY_WEB_HOST = '0.0.0.0'
SENTRY_WEB_PORT = ${SENTRY_PORT}

SECRET_KEY = '$(openssl rand -hex 32)'

SENTRY_SINGLE_ORGANIZATION = True
EOF
    
    # Create systemd service (Linux only)
    if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v systemctl &> /dev/null; then
        sudo tee /etc/systemd/system/sentry-web.service > /dev/null <<EOF
[Unit]
Description=Sentry Web Service
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=sentry
WorkingDirectory=${SENTRY_DATA_DIR}
Environment=SENTRY_CONF=${SENTRY_DATA_DIR}/config
ExecStart=${SENTRY_DATA_DIR}/venv/bin/sentry run web
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        sudo tee /etc/systemd/system/sentry-worker.service > /dev/null <<EOF
[Unit]
Description=Sentry Worker Service
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=sentry
WorkingDirectory=${SENTRY_DATA_DIR}
Environment=SENTRY_CONF=${SENTRY_DATA_DIR}/config
ExecStart=${SENTRY_DATA_DIR}/venv/bin/sentry run worker
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        sudo tee /etc/systemd/system/sentry-cron.service > /dev/null <<EOF
[Unit]
Description=Sentry Cron Service
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=sentry
WorkingDirectory=${SENTRY_DATA_DIR}
Environment=SENTRY_CONF=${SENTRY_DATA_DIR}/config
ExecStart=${SENTRY_DATA_DIR}/venv/bin/sentry run cron
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        # Create sentry user
        sudo useradd -r -s /bin/false sentry 2>/dev/null || true
        sudo chown -R sentry:sentry "$SENTRY_DATA_DIR"
        
        # Initialize database
        sudo -u sentry SENTRY_CONF="$SENTRY_DATA_DIR/config" "$SENTRY_DATA_DIR/venv/bin/sentry" upgrade --noinput
        
        # Create superuser
        sudo -u sentry SENTRY_CONF="$SENTRY_DATA_DIR/config" "$SENTRY_DATA_DIR/venv/bin/sentry" createuser --email admin@example.com --password admin --superuser --no-input
        
        # Start services
        sudo systemctl daemon-reload
        sudo systemctl enable sentry-web sentry-worker sentry-cron
        sudo systemctl start sentry-web sentry-worker sentry-cron
        
        echo "Sentry services started."
    else
        echo "Manual setup required. Run the following commands:"
        echo "SENTRY_CONF=$SENTRY_DATA_DIR/config $SENTRY_DATA_DIR/venv/bin/sentry upgrade --noinput"
        echo "SENTRY_CONF=$SENTRY_DATA_DIR/config $SENTRY_DATA_DIR/venv/bin/sentry createuser --email admin@example.com --password admin --superuser"
        echo "SENTRY_CONF=$SENTRY_DATA_DIR/config $SENTRY_DATA_DIR/venv/bin/sentry run web"
    fi
fi

# Test installation
echo "Testing Sentry installation..."
sleep 10

if curl -f "http://localhost:$SENTRY_PORT/_health/" &>/dev/null; then
    echo "✅ Sentry is running successfully!"
    echo "📊 Access Sentry at: http://localhost:$SENTRY_PORT"
    echo "👤 Default login: admin@example.com / admin"
    echo ""
    echo "📚 Next steps:"
    echo "1. Visit http://localhost:$SENTRY_PORT to access the web interface"
    echo "2. Create a new project"
    echo "3. Configure your application to send errors to Sentry"
else
    echo "❌ Error: Sentry is not responding"
    exit 1
fi

echo "Sentry installation completed successfully!"