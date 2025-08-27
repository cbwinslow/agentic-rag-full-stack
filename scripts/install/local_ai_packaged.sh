#!/usr/bin/env bash
set -euo pipefail

# scripts/install/local_ai_packaged.sh
# Install local-ai-packaged from GitHub repo
# This is a packaged version of LocalAI with additional models and configurations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
REPO_URL="${REPO_URL:-https://github.com/go-skynet/LocalAI}"
LOCAL_AI_PORT="${LOCAL_AI_PORT:-8082}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
LOCAL_AI_DATA_DIR="${PROJECT_ROOT}/data/local-ai-packaged"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--port PORT] [--repo URL] [--data-dir DIR]"
    echo "  --docker       Install using Docker (default)"
    echo "  --bare-metal   Install from source"
    echo "  --port PORT    Set LocalAI port (default: 8082)"
    echo "  --repo URL     GitHub repository URL"
    echo "  --data-dir     Set data directory (default: ./data/local-ai-packaged)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --port) LOCAL_AI_PORT="$2"; shift 2 ;;
        --repo) REPO_URL="$2"; shift 2 ;;
        --data-dir) LOCAL_AI_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing Local AI Packaged..."
echo "Installation type: $INSTALL_TYPE"
echo "Port: $LOCAL_AI_PORT"
echo "Repository: $REPO_URL"
echo "Data directory: $LOCAL_AI_DATA_DIR"

# Create data directory
mkdir -p "$LOCAL_AI_DATA_DIR"/{models,galleries,config}

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing Local AI Packaged using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Create configuration for LocalAI with preloaded models
    cat > "$LOCAL_AI_DATA_DIR/config/models.yaml" <<EOF
# Local AI Packaged Configuration with Popular Models

# Text Generation Models
- name: gpt-3.5-turbo
  backend: llama
  parameters:
    model: ggml-gpt4all-j-v1.3-groovy.bin
    temperature: 0.7
    top_k: 80
    top_p: 0.8
    max_tokens: 2048

- name: codellama
  backend: llama
  parameters:
    model: codellama-7b-instruct.q4_0.bin
    temperature: 0.2
    top_k: 40
    top_p: 0.95
    max_tokens: 2048

- name: llama2-chat
  backend: llama
  parameters:
    model: llama-2-7b-chat.q4_0.bin
    temperature: 0.8
    top_k: 40
    top_p: 0.9
    max_tokens: 2048

# Embedding Models
- name: text-embedding-ada-002
  backend: bert-embeddings
  parameters:
    model: all-MiniLM-L6-v2

# Image Generation
- name: stablediffusion
  backend: stablediffusion
  parameters:
    model: stablediffusion_assets
EOF

    # Create galleries configuration for easy model downloads
    cat > "$LOCAL_AI_DATA_DIR/config/galleries.yaml" <<EOF
galleries:
  - name: "huggingface"
    url: "github:go-skynet/model-gallery/huggingface.yaml"
  - name: "openllama"
    url: "github:go-skynet/model-gallery/openllama.yaml"
  - name: "gpt4all"
    url: "github:go-skynet/model-gallery/gpt4all.yaml"
  - name: "llama2"
    url: "github:go-skynet/model-gallery/llama2.yaml"
EOF

    # Create docker-compose configuration
    cat > "$PROJECT_ROOT/docker-compose.local-ai-packaged.yml" <<EOF
version: '3.8'
services:
  local-ai-packaged:
    image: localai/localai:latest-aio-gpu
    ports:
      - "${LOCAL_AI_PORT}:8080"
    volumes:
      - ${LOCAL_AI_DATA_DIR}/models:/models:cached
      - ${LOCAL_AI_DATA_DIR}/config:/config:ro
    environment:
      - DEBUG=true
      - MODELS_PATH=/models
      - GALLERIES='[{"name":"model-gallery", "url":"github:go-skynet/model-gallery/index.yaml"}, {"name":"huggingface", "url":"github:go-skynet/model-gallery/huggingface.yaml"}]'
      - PRELOAD_MODELS='[{"url": "github:go-skynet/model-gallery/gpt4all-j.yaml", "name": "gpt-3.5-turbo"}, {"url": "github:go-skynet/model-gallery/bert-embeddings.yaml", "name": "text-embedding-ada-002"}]'
      - CONTEXTS_CUTOFFS='{"gpt-3.5-turbo": 4096, "codellama": 4096, "llama2-chat": 4096}'
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/readiness"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  # Model download helper
  model-downloader:
    image: curlimages/curl:latest
    volumes:
      - ${LOCAL_AI_DATA_DIR}/models:/models
    entrypoint: >
      sh -c "
        echo 'Downloading popular models...'
        mkdir -p /models
        curl -L 'https://gpt4all.io/models/ggml-gpt4all-j-v1.3-groovy.bin' -o /models/ggml-gpt4all-j-v1.3-groovy.bin || true
        curl -L 'https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGML/resolve/main/codellama-7b-instruct.q4_0.bin' -o /models/codellama-7b-instruct.q4_0.bin || true
        echo 'Model download completed'
      "
    profiles: ["download"]
EOF
    
    echo "Starting model download..."
    docker compose -f "$PROJECT_ROOT/docker-compose.local-ai-packaged.yml" --profile download up model-downloader
    
    echo "Starting Local AI Packaged container..."
    docker compose -f "$PROJECT_ROOT/docker-compose.local-ai-packaged.yml" up -d local-ai-packaged
    
    echo "Waiting for Local AI Packaged to be ready..."
    sleep 30
    
    # Wait for LocalAI to be ready
    max_attempts=60  # Longer wait time for model loading
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$LOCAL_AI_PORT/readiness" &>/dev/null; then
            echo "Local AI Packaged is ready!"
            break
        fi
        echo "Waiting for Local AI Packaged... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: Local AI Packaged failed to start within expected time"
        exit 1
    fi
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Installing Local AI Packaged from source..."
    
    # Check dependencies
    if ! command -v go &> /dev/null; then
        echo "Error: Go is not installed. Please install Go 1.19+ first."
        exit 1
    fi
    
    # Clone repository
    if [ ! -d "$LOCAL_AI_DATA_DIR/LocalAI" ]; then
        echo "Cloning LocalAI repository..."
        git clone "$REPO_URL" "$LOCAL_AI_DATA_DIR/LocalAI"
    fi
    
    cd "$LOCAL_AI_DATA_DIR/LocalAI"
    
    # Build LocalAI
    echo "Building LocalAI..."
    make build
    
    # Create systemd service (Linux only)
    if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v systemctl &> /dev/null; then
        sudo tee /etc/systemd/system/local-ai-packaged.service > /dev/null <<EOF
[Unit]
Description=Local AI Packaged Service
After=network.target

[Service]
Type=simple
User=localai
WorkingDirectory=${LOCAL_AI_DATA_DIR}/LocalAI
ExecStart=${LOCAL_AI_DATA_DIR}/LocalAI/local-ai --address 0.0.0.0:${LOCAL_AI_PORT} --models-path ${LOCAL_AI_DATA_DIR}/models
Restart=always
RestartSec=5
Environment=MODELS_PATH=${LOCAL_AI_DATA_DIR}/models

[Install]
WantedBy=multi-user.target
EOF
        
        # Create localai user
        sudo useradd -r -s /bin/false localai 2>/dev/null || true
        sudo chown -R localai:localai "$LOCAL_AI_DATA_DIR"
        
        # Start service
        sudo systemctl daemon-reload
        sudo systemctl enable local-ai-packaged
        sudo systemctl start local-ai-packaged
        
        echo "Local AI Packaged service started."
    else
        echo "Manual setup required. Run the following command:"
        echo "$LOCAL_AI_DATA_DIR/LocalAI/local-ai --address 0.0.0.0:$LOCAL_AI_PORT --models-path $LOCAL_AI_DATA_DIR/models"
    fi
fi

# Test installation and show available models
echo "Testing Local AI Packaged installation..."
sleep 10

if curl -f "http://localhost:$LOCAL_AI_PORT/readiness" &>/dev/null; then
    echo "✅ Local AI Packaged is running successfully!"
    echo "🤖 API Endpoint: http://localhost:$LOCAL_AI_PORT"
    echo ""
    echo "Available models:"
    curl -s "http://localhost:$LOCAL_AI_PORT/v1/models" | jq '.data[].id' 2>/dev/null || echo "  - Check /v1/models endpoint for available models"
    echo ""
    echo "📚 Usage examples:"
    echo "  # Chat completion"
    echo "  curl http://localhost:$LOCAL_AI_PORT/v1/chat/completions \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\": \"gpt-3.5-turbo\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]}'"
    echo ""
    echo "  # Text embeddings"
    echo "  curl http://localhost:$LOCAL_AI_PORT/v1/embeddings \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\": \"text-embedding-ada-002\", \"input\": \"Hello world\"}'"
else
    echo "❌ Error: Local AI Packaged is not responding"
    exit 1
fi

echo "Local AI Packaged installation completed successfully!"