#!/usr/bin/env bash
set -euo pipefail

# scripts/install/grafana.sh
# Install Grafana for monitoring dashboards and visualization
# Supports both Docker and bare metal installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
GRAFANA_VERSION="${GRAFANA_VERSION:-10.2.2}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
GRAFANA_DATA_DIR="${PROJECT_ROOT}/data/grafana"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--port PORT] [--data-dir DIR]"
    echo "  --docker       Install using Docker (default)"
    echo "  --bare-metal   Install directly on host system"
    echo "  --port PORT    Set Grafana port (default: 3000)"
    echo "  --data-dir     Set data directory (default: ./data/grafana)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --port) GRAFANA_PORT="$2"; shift 2 ;;
        --data-dir) GRAFANA_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing Grafana monitoring platform..."
echo "Installation type: $INSTALL_TYPE"
echo "Port: $GRAFANA_PORT"
echo "Data directory: $GRAFANA_DATA_DIR"

# Create data directory
mkdir -p "$GRAFANA_DATA_DIR"/{data,logs,plugins,provisioning/{dashboards,datasources,notifiers}}

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing Grafana using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Create Grafana configuration
    cat > "$GRAFANA_DATA_DIR/grafana.ini" <<EOF
[server]
http_port = 3000
domain = localhost

[security]
admin_user = admin
admin_password = admin

[analytics]
reporting_enabled = false
check_for_updates = false

[log]
mode = console
level = info

[plugins]
enable_alpha = true
EOF

    # Create datasources configuration
    cat > "$GRAFANA_DATA_DIR/provisioning/datasources/datasources.yml" <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
  
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
  
  - name: OpenSearch
    type: opensearch
    access: proxy
    url: http://opensearch-node1:9200
    database: logs-*
    basicAuth: false
  
  - name: ClickHouse
    type: grafana-clickhouse-datasource
    access: proxy
    url: http://clickhouse:8123
    basicAuth: false
EOF

    # Create sample dashboard
    cat > "$GRAFANA_DATA_DIR/provisioning/dashboards/dashboards.yml" <<EOF
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

    cat > "$GRAFANA_DATA_DIR/provisioning/dashboards/system-overview.json" <<'EOF'
{
  "dashboard": {
    "id": null,
    "title": "System Overview",
    "tags": ["system"],
    "style": "dark",
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "CPU Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "5s"
  }
}
EOF
    
    # Create docker-compose configuration for Grafana
    cat > "$PROJECT_ROOT/docker-compose.grafana.yml" <<EOF
version: '3.8'
services:
  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    ports:
      - "${GRAFANA_PORT}:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ${GRAFANA_DATA_DIR}/grafana.ini:/etc/grafana/grafana.ini:ro
      - ${GRAFANA_DATA_DIR}/provisioning:/etc/grafana/provisioning:ro
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_INSTALL_PLUGINS=grafana-clickhouse-datasource,grafana-opensearch-datasource
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    user: "472"

volumes:
  grafana_data:
EOF
    
    echo "Starting Grafana container..."
    docker compose -f "$PROJECT_ROOT/docker-compose.grafana.yml" up -d
    
    echo "Waiting for Grafana to be ready..."
    sleep 15
    
    # Wait for Grafana to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$GRAFANA_PORT/api/health" &>/dev/null; then
            echo "Grafana is ready!"
            break
        fi
        echo "Waiting for Grafana... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: Grafana failed to start within expected time"
        exit 1
    fi
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Installing Grafana on bare metal..."
    
    # Detect OS and install Grafana
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Install on Linux
        if command -v apt-get &> /dev/null; then
            # Ubuntu/Debian
            echo "Installing Grafana on Ubuntu/Debian..."
            sudo apt-get install -y software-properties-common
            sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
            wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
            sudo apt-get update
            sudo apt-get install -y grafana
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS
            echo "Installing Grafana on RHEL/CentOS..."
            sudo tee /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
            sudo yum install -y grafana
        else
            echo "Error: Unsupported Linux distribution"
            exit 1
        fi
        
        # Configure Grafana
        sudo tee /etc/grafana/grafana.ini > /dev/null <<EOF
[server]
http_port = ${GRAFANA_PORT}
domain = localhost

[security]
admin_user = admin
admin_password = admin

[analytics]
reporting_enabled = false
check_for_updates = false
EOF
        
        # Start Grafana service
        sudo systemctl daemon-reload
        sudo systemctl enable grafana-server
        sudo systemctl start grafana-server
        
        echo "Grafana service started. Use 'sudo systemctl status grafana-server' to check status."
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Install on macOS
        echo "Installing Grafana on macOS..."
        if command -v brew &> /dev/null; then
            brew install grafana
            brew services start grafana
        else
            echo "Error: Homebrew is required for macOS installation"
            exit 1
        fi
    else
        echo "Error: Unsupported OS: $OSTYPE"
        exit 1
    fi
fi

# Test installation
echo "Testing Grafana installation..."
sleep 5

if curl -f "http://localhost:$GRAFANA_PORT/api/health" &>/dev/null; then
    echo "✅ Grafana is running successfully!"
    echo "📊 Access Grafana at: http://localhost:$GRAFANA_PORT"
    echo "👤 Default login: admin / admin"
    echo ""
    echo "📚 Available features:"
    echo "   - System Overview Dashboard"
    echo "   - Prometheus Data Source"
    echo "   - Loki Data Source"
    echo "   - OpenSearch Data Source"
    echo "   - ClickHouse Data Source"
else
    echo "❌ Error: Grafana is not responding"
    exit 1
fi

echo "Grafana installation completed successfully!"