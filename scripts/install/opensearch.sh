#!/usr/bin/env bash
set -euo pipefail

# scripts/install/opensearch.sh
# Install OpenSearch with Dashboards for search and analytics
# Supports both Docker and bare metal installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
OPENSEARCH_VERSION="${OPENSEARCH_VERSION:-2.11.1}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
DASHBOARDS_PORT="${DASHBOARDS_PORT:-5601}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
OPENSEARCH_DATA_DIR="${PROJECT_ROOT}/data/opensearch"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--opensearch-port PORT] [--dashboards-port PORT] [--data-dir DIR]"
    echo "  --docker             Install using Docker (default)"
    echo "  --bare-metal         Install directly on host system"
    echo "  --opensearch-port    Set OpenSearch port (default: 9200)"
    echo "  --dashboards-port    Set Dashboards port (default: 5601)"
    echo "  --data-dir           Set data directory (default: ./data/opensearch)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --opensearch-port) OPENSEARCH_PORT="$2"; shift 2 ;;
        --dashboards-port) DASHBOARDS_PORT="$2"; shift 2 ;;
        --data-dir) OPENSEARCH_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing OpenSearch with Dashboards..."
echo "Installation type: $INSTALL_TYPE"
echo "OpenSearch Port: $OPENSEARCH_PORT"
echo "Dashboards Port: $DASHBOARDS_PORT"
echo "Data directory: $OPENSEARCH_DATA_DIR"

# Create data directory
mkdir -p "$OPENSEARCH_DATA_DIR"

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing OpenSearch using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Create docker-compose configuration for OpenSearch
    cat > "$PROJECT_ROOT/docker-compose.opensearch.yml" <<EOF
version: '3.8'
services:
  opensearch-node1:
    image: opensearchproject/opensearch:${OPENSEARCH_VERSION}
    container_name: opensearch-node1
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-node1
      - discovery.seed_hosts=opensearch-node1
      - cluster.initial_cluster_manager_nodes=opensearch-node1
      - bootstrap.memory_lock=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
      - OPENSEARCH_INITIAL_ADMIN_PASSWORD=admin
      - plugins.security.disabled=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - opensearch-data1:/usr/share/opensearch/data
    ports:
      - ${OPENSEARCH_PORT}:9200
      - 9600:9600
    networks:
      - opensearch-net
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  opensearch-dashboards:
    image: opensearchproject/opensearch-dashboards:${OPENSEARCH_VERSION}
    container_name: opensearch-dashboards
    ports:
      - ${DASHBOARDS_PORT}:5601
    expose:
      - "5601"
    environment:
      OPENSEARCH_HOSTS: '["http://opensearch-node1:9200"]'
      OPENSEARCH_USERNAME: admin
      OPENSEARCH_PASSWORD: admin
      DISABLE_SECURITY_DASHBOARDS_PLUGIN: true
    networks:
      - opensearch-net
    depends_on:
      opensearch-node1:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5601/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 60s

volumes:
  opensearch-data1:

networks:
  opensearch-net:
EOF
    
    echo "Starting OpenSearch containers..."
    docker compose -f "$PROJECT_ROOT/docker-compose.opensearch.yml" up -d
    
    echo "Waiting for OpenSearch to be ready..."
    sleep 30
    
    # Wait for OpenSearch to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$OPENSEARCH_PORT/_cluster/health" &>/dev/null; then
            echo "OpenSearch is ready!"
            break
        fi
        echo "Waiting for OpenSearch... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: OpenSearch failed to start within expected time"
        exit 1
    fi
    
    # Wait for Dashboards to be ready
    echo "Waiting for OpenSearch Dashboards to be ready..."
    max_attempts=20
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$DASHBOARDS_PORT/api/status" &>/dev/null; then
            echo "OpenSearch Dashboards is ready!"
            break
        fi
        echo "Waiting for Dashboards... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Installing OpenSearch on bare metal..."
    
    # Detect OS and install OpenSearch
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Install on Linux
        if command -v apt-get &> /dev/null; then
            # Ubuntu/Debian
            echo "Installing OpenSearch on Ubuntu/Debian..."
            curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
            echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | sudo tee /etc/apt/sources.list.d/opensearch-2.x.list
            sudo apt-get update
            sudo OPENSEARCH_INITIAL_ADMIN_PASSWORD=admin apt-get install -y opensearch opensearch-dashboards
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS
            echo "Installing OpenSearch on RHEL/CentOS..."
            sudo curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo -o /etc/yum.repos.d/opensearch-2.x.repo
            sudo OPENSEARCH_INITIAL_ADMIN_PASSWORD=admin yum install -y opensearch opensearch-dashboards
        else
            echo "Error: Unsupported Linux distribution"
            exit 1
        fi
        
        # Configure OpenSearch
        sudo tee /etc/opensearch/opensearch.yml > /dev/null <<EOF
cluster.name: opensearch-cluster
node.name: node-1
path.data: /var/lib/opensearch
path.logs: /var/log/opensearch
network.host: 0.0.0.0
http.port: ${OPENSEARCH_PORT}
discovery.type: single-node
plugins.security.disabled: true
EOF
        
        # Configure OpenSearch Dashboards
        sudo tee /etc/opensearch-dashboards/opensearch_dashboards.yml > /dev/null <<EOF
server.port: ${DASHBOARDS_PORT}
server.host: "0.0.0.0"
opensearch.hosts: ["http://localhost:${OPENSEARCH_PORT}"]
opensearch.username: admin
opensearch.password: admin
opensearch_security.multitenancy.enabled: false
opensearch_security.disabled: true
EOF
        
        # Start services
        sudo systemctl daemon-reload
        sudo systemctl enable opensearch opensearch-dashboards
        sudo systemctl start opensearch
        sleep 30
        sudo systemctl start opensearch-dashboards
        
        echo "OpenSearch services started."
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Install on macOS
        echo "Installing OpenSearch on macOS..."
        echo "Please install manually from https://opensearch.org/downloads.html"
        exit 1
    else
        echo "Error: Unsupported OS: $OSTYPE"
        exit 1
    fi
fi

# Install sample dashboards and visualizations
echo "Installing sample dashboards..."
sleep 5

# Create sample index patterns and dashboards
curl -X PUT "localhost:$OPENSEARCH_PORT/logs-*" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "level": { "type": "keyword" },
      "message": { "type": "text" },
      "service": { "type": "keyword" },
      "host": { "type": "keyword" }
    }
  }
}' 2>/dev/null || true

curl -X PUT "localhost:$OPENSEARCH_PORT/metrics-*" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "metric_name": { "type": "keyword" },
      "value": { "type": "double" },
      "service": { "type": "keyword" },
      "host": { "type": "keyword" }
    }
  }
}' 2>/dev/null || true

# Test installation
echo "Testing OpenSearch installation..."
sleep 5

if curl -f "http://localhost:$OPENSEARCH_PORT/_cluster/health" &>/dev/null; then
    echo "✅ OpenSearch is running successfully!"
    echo "📊 OpenSearch API: http://localhost:$OPENSEARCH_PORT"
    echo "📈 OpenSearch Dashboards: http://localhost:$DASHBOARDS_PORT"
    echo ""
    echo "Example usage:"
    echo "curl http://localhost:$OPENSEARCH_PORT/_cluster/health"
    echo "curl http://localhost:$OPENSEARCH_PORT/_cat/indices"
else
    echo "❌ Error: OpenSearch is not responding"
    exit 1
fi

echo "OpenSearch installation completed successfully!"
echo ""
echo "📚 Access the following dashboards:"
echo "   - Main Dashboard: http://localhost:$DASHBOARDS_PORT"
echo "   - Dev Tools: http://localhost:$DASHBOARDS_PORT/app/dev_tools"
echo "   - Index Management: http://localhost:$DASHBOARDS_PORT/app/im"
echo "   - Discover: http://localhost:$DASHBOARDS_PORT/app/discover"