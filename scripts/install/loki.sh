#!/usr/bin/env bash
set -euo pipefail

# scripts/install/loki.sh
# Install Loki for log aggregation and analysis
# Supports both Docker and bare metal installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
LOKI_VERSION="${LOKI_VERSION:-2.9.2}"
LOKI_PORT="${LOKI_PORT:-3100}"
PROMTAIL_PORT="${PROMTAIL_PORT:-9080}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
LOKI_DATA_DIR="${PROJECT_ROOT}/data/loki"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--loki-port PORT] [--promtail-port PORT] [--data-dir DIR]"
    echo "  --docker         Install using Docker (default)"
    echo "  --bare-metal     Install directly on host system"
    echo "  --loki-port      Set Loki port (default: 3100)"
    echo "  --promtail-port  Set Promtail port (default: 9080)"
    echo "  --data-dir       Set data directory (default: ./data/loki)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --loki-port) LOKI_PORT="$2"; shift 2 ;;
        --promtail-port) PROMTAIL_PORT="$2"; shift 2 ;;
        --data-dir) LOKI_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing Loki log aggregation system..."
echo "Installation type: $INSTALL_TYPE"
echo "Loki Port: $LOKI_PORT"
echo "Promtail Port: $PROMTAIL_PORT"
echo "Data directory: $LOKI_DATA_DIR"

# Create data directory
mkdir -p "$LOKI_DATA_DIR"/{loki,promtail}

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing Loki using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Create Loki configuration
    cat > "$LOKI_DATA_DIR/loki-config.yml" <<EOF
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

analytics:
  reporting_enabled: false
EOF
    
    # Create Promtail configuration
    cat > "$LOKI_DATA_DIR/promtail-config.yml" <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    static_configs:
      - targets:
          - localhost
        labels:
          job: containerlogs
          __path__: /var/log/containers/*.log

  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*.log

  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        target_label: 'container'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'logstream'
      - source_labels: ['__meta_docker_container_label_logging']
        target_label: 'logging'
    pipeline_stages:
      - docker: {}
EOF
    
    # Create docker-compose configuration for Loki
    cat > "$PROJECT_ROOT/docker-compose.loki.yml" <<EOF
version: '3.8'
services:
  loki:
    image: grafana/loki:${LOKI_VERSION}
    ports:
      - "${LOKI_PORT}:3100"
    volumes:
      - ${LOKI_DATA_DIR}/loki-config.yml:/etc/loki/local-config.yaml:ro
      - loki_data:/loki
    command: -config.file=/etc/loki/local-config.yaml
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  promtail:
    image: grafana/promtail:${LOKI_VERSION}
    ports:
      - "${PROMTAIL_PORT}:9080"
    volumes:
      - ${LOKI_DATA_DIR}/promtail-config.yml:/etc/promtail/config.yml:ro
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock
    command: -config.file=/etc/promtail/config.yml
    restart: unless-stopped
    depends_on:
      loki:
        condition: service_healthy

volumes:
  loki_data:
EOF
    
    echo "Starting Loki containers..."
    docker compose -f "$PROJECT_ROOT/docker-compose.loki.yml" up -d
    
    echo "Waiting for Loki to be ready..."
    sleep 15
    
    # Wait for Loki to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$LOKI_PORT/ready" &>/dev/null; then
            echo "Loki is ready!"
            break
        fi
        echo "Waiting for Loki... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: Loki failed to start within expected time"
        exit 1
    fi
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Installing Loki on bare metal..."
    
    # Detect OS and architecture
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="darwin"
    else
        echo "Error: Unsupported OS: $OSTYPE"
        exit 1
    fi
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) echo "Error: Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    # Download Loki and Promtail binaries
    TEMP_DIR=$(mktemp -d)
    
    echo "Downloading Loki..."
    curl -L "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-${OS}-${ARCH}.zip" -o "$TEMP_DIR/loki.zip"
    unzip "$TEMP_DIR/loki.zip" -d "$TEMP_DIR"
    sudo cp "$TEMP_DIR/loki-${OS}-${ARCH}" /usr/local/bin/loki
    sudo chmod +x /usr/local/bin/loki
    
    echo "Downloading Promtail..."
    curl -L "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/promtail-${OS}-${ARCH}.zip" -o "$TEMP_DIR/promtail.zip"
    unzip "$TEMP_DIR/promtail.zip" -d "$TEMP_DIR"
    sudo cp "$TEMP_DIR/promtail-${OS}-${ARCH}" /usr/local/bin/promtail
    sudo chmod +x /usr/local/bin/promtail
    
    # Create configuration files (same as Docker version)
    cat > "$LOKI_DATA_DIR/loki-config.yml" <<EOF
auth_enabled: false

server:
  http_listen_port: ${LOKI_PORT}
  grpc_listen_port: 9096

common:
  path_prefix: ${LOKI_DATA_DIR}/loki
  storage:
    filesystem:
      chunks_directory: ${LOKI_DATA_DIR}/loki/chunks
      rules_directory: ${LOKI_DATA_DIR}/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

analytics:
  reporting_enabled: false
EOF
    
    cat > "$LOKI_DATA_DIR/promtail-config.yml" <<EOF
server:
  http_listen_port: ${PROMTAIL_PORT}
  grpc_listen_port: 0

positions:
  filename: ${LOKI_DATA_DIR}/promtail/positions.yaml

clients:
  - url: http://localhost:${LOKI_PORT}/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*.log
EOF
    
    # Create systemd services (Linux only)
    if [[ "$OS" == "linux" ]] && command -v systemctl &> /dev/null; then
        sudo tee /etc/systemd/system/loki.service > /dev/null <<EOF
[Unit]
Description=Loki Log Aggregation System
After=network.target

[Service]
Type=simple
User=loki
WorkingDirectory=${LOKI_DATA_DIR}
ExecStart=/usr/local/bin/loki -config.file=${LOKI_DATA_DIR}/loki-config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        sudo tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit]
Description=Promtail Log Agent
After=network.target loki.service
Requires=loki.service

[Service]
Type=simple
User=promtail
WorkingDirectory=${LOKI_DATA_DIR}
ExecStart=/usr/local/bin/promtail -config.file=${LOKI_DATA_DIR}/promtail-config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        # Create users
        sudo useradd -r -s /bin/false loki 2>/dev/null || true
        sudo useradd -r -s /bin/false promtail 2>/dev/null || true
        sudo chown -R loki:loki "$LOKI_DATA_DIR"
        sudo usermod -a -G adm promtail  # Allow promtail to read logs
        
        # Start services
        sudo systemctl daemon-reload
        sudo systemctl enable loki promtail
        sudo systemctl start loki
        sleep 5
        sudo systemctl start promtail
        
        echo "Loki services started."
    else
        echo "Manual setup required. Run the following commands:"
        echo "loki -config.file=$LOKI_DATA_DIR/loki-config.yml"
        echo "promtail -config.file=$LOKI_DATA_DIR/promtail-config.yml"
    fi
    
    # Cleanup
    rm -rf "$TEMP_DIR"
fi

# Test installation
echo "Testing Loki installation..."
sleep 5

if curl -f "http://localhost:$LOKI_PORT/ready" &>/dev/null; then
    echo "✅ Loki is running successfully!"
    echo "📊 Loki API: http://localhost:$LOKI_PORT"
    echo "📈 Promtail metrics: http://localhost:$PROMTAIL_PORT/metrics"
    echo ""
    echo "Example queries:"
    echo "curl 'http://localhost:$LOKI_PORT/loki/api/v1/query_range?query={job=\"varlogs\"}&start=\$(date -d '1 hour ago' -u +%s)000000000&end=\$(date -u +%s)000000000'"
else
    echo "❌ Error: Loki is not responding"
    exit 1
fi

echo "Loki installation completed successfully!"