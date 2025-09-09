#!/usr/bin/env bash
set -euo pipefail

# scripts/install/weaviate.sh
# Install Weaviate vector database for semantic search and AI applications
# Supports both Docker and bare metal installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
WEAVIATE_VERSION="${WEAVIATE_VERSION:-1.25.5}"
WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
WEAVIATE_GRPC_PORT="${WEAVIATE_GRPC_PORT:-50051}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
WEAVIATE_DATA_DIR="${PROJECT_ROOT}/data/weaviate"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--port PORT] [--data-dir DIR]"
    echo "  --docker       Install using Docker (default)"
    echo "  --bare-metal   Install directly on host system"
    echo "  --port PORT    Set Weaviate port (default: 8080)"
    echo "  --data-dir DIR Set data directory (default: ./data/weaviate)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --port) WEAVIATE_PORT="$2"; shift 2 ;;
        --data-dir) WEAVIATE_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing Weaviate vector database..."
echo "Installation type: $INSTALL_TYPE"
echo "Port: $WEAVIATE_PORT"
echo "Data directory: $WEAVIATE_DATA_DIR"

# Create data directory
mkdir -p "$WEAVIATE_DATA_DIR"

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing Weaviate using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Create docker-compose configuration for Weaviate
    cat > "$PROJECT_ROOT/docker-compose.weaviate.yml" <<EOF
version: '3.8'
services:
  weaviate:
    image: semitechnologies/weaviate:${WEAVIATE_VERSION}
    ports:
      - "${WEAVIATE_PORT}:8080"
      - "${WEAVIATE_GRPC_PORT}:50051"
    volumes:
      - weaviate_data:/var/lib/weaviate
    restart: unless-stopped
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      DEFAULT_VECTORIZER_MODULE: 'none'
      ENABLE_MODULES: 'text2vec-openai,text2vec-cohere,text2vec-huggingface,ref2vec-centroid,generative-openai,qna-openai'
      CLUSTER_HOSTNAME: 'node1'
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=3", "--spider", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

volumes:
  weaviate_data:
EOF
    
    echo "Starting Weaviate container..."
    docker compose -f "$PROJECT_ROOT/docker-compose.weaviate.yml" up -d
    
    echo "Waiting for Weaviate to be ready..."
    sleep 10
    
    # Wait for Weaviate to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$WEAVIATE_PORT/v1/.well-known/ready" &>/dev/null; then
            echo "Weaviate is ready!"
            break
        fi
        echo "Waiting for Weaviate... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: Weaviate failed to start within expected time"
        exit 1
    fi
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Installing Weaviate on bare metal..."
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="darwin"
    else
        echo "Error: Unsupported OS: $OSTYPE"
        exit 1
    fi
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) echo "Error: Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    # Download Weaviate binary
    WEAVIATE_URL="https://github.com/weaviate/weaviate/releases/download/v${WEAVIATE_VERSION}/weaviate-${WEAVIATE_VERSION}-${OS}-${ARCH}.tar.gz"
    TEMP_DIR=$(mktemp -d)
    
    echo "Downloading Weaviate from $WEAVIATE_URL"
    curl -L "$WEAVIATE_URL" | tar -xz -C "$TEMP_DIR"
    
    # Install binary
    sudo cp "$TEMP_DIR/weaviate" /usr/local/bin/
    sudo chmod +x /usr/local/bin/weaviate
    
    # Create configuration file
    cat > "$WEAVIATE_DATA_DIR/config.yaml" <<EOF
origin: http://localhost:${WEAVIATE_PORT}
persistence:
  dataPath: "${WEAVIATE_DATA_DIR}"
authentication:
  anonymous_access:
    enabled: true
authorization:
  admin_list:
    enabled: false
query_defaults:
  limit: 25
modules:
  text2vec-openai:
    enabled: true
  text2vec-cohere:
    enabled: true
  text2vec-huggingface:
    enabled: true
  ref2vec-centroid:
    enabled: true
  generative-openai:
    enabled: true
  qna-openai:
    enabled: true
EOF
    
    # Create systemd service (Linux only)
    if [[ "$OS" == "linux" ]] && command -v systemctl &> /dev/null; then
        sudo tee /etc/systemd/system/weaviate.service > /dev/null <<EOF
[Unit]
Description=Weaviate Vector Database
After=network.target

[Service]
Type=simple
User=weaviate
WorkingDirectory=${WEAVIATE_DATA_DIR}
ExecStart=/usr/local/bin/weaviate --host 0.0.0.0 --port ${WEAVIATE_PORT} --scheme http --config-file ${WEAVIATE_DATA_DIR}/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        # Create weaviate user
        sudo useradd -r -s /bin/false weaviate 2>/dev/null || true
        sudo chown -R weaviate:weaviate "$WEAVIATE_DATA_DIR"
        
        # Start service
        sudo systemctl daemon-reload
        sudo systemctl enable weaviate
        sudo systemctl start weaviate
        
        echo "Weaviate service started. Use 'sudo systemctl status weaviate' to check status."
    else
        echo "Starting Weaviate manually..."
        echo "To start Weaviate, run: weaviate --host 0.0.0.0 --port $WEAVIATE_PORT --scheme http --config-file $WEAVIATE_DATA_DIR/config.yaml"
    fi
    
    # Cleanup
    rm -rf "$TEMP_DIR"
fi

# Test installation
echo "Testing Weaviate installation..."
sleep 5

if curl -f "http://localhost:$WEAVIATE_PORT/v1/.well-known/ready" &>/dev/null; then
    echo "✅ Weaviate is running successfully!"
    echo "📊 Access Weaviate at: http://localhost:$WEAVIATE_PORT"
    echo "📚 API Documentation: http://localhost:$WEAVIATE_PORT/v1"
    echo ""
    echo "Example usage:"
    echo "curl http://localhost:$WEAVIATE_PORT/v1/meta"
else
    echo "❌ Error: Weaviate is not responding"
    exit 1
fi

echo "Weaviate installation completed successfully!"