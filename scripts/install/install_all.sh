#!/usr/bin/env bash
set -euo pipefail

# scripts/install/install_all.sh
# Master installation script for all services
# Installs and configures the complete agentic RAG full-stack platform

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
SERVICES_TO_INSTALL="${SERVICES_TO_INSTALL:-all}"
DRY_RUN="${DRY_RUN:-false}"

# Available services
AVAILABLE_SERVICES=(
    "postgresql"
    "pgvector" 
    "supabase"
    "qdrant"
    "weaviate"
    "clickhouse"
    "opensearch"
    "openwebui"
    "localai"
    "flowise"
    "n8n"
    "langfuse"
    "sentry"
    "prometheus"
    "grafana"
    "loki"
    "ai-orchestrator"
)

# Service categories
CORE_SERVICES=("postgresql" "pgvector" "supabase" "qdrant")
AI_SERVICES=("openwebui" "localai" "flowise" "langfuse" "ai-orchestrator")
ANALYTICS_SERVICES=("clickhouse" "opensearch")
MONITORING_SERVICES=("prometheus" "grafana" "loki" "sentry")
WORKFLOW_SERVICES=("n8n")
VECTOR_SERVICES=("qdrant" "weaviate")

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --docker              Install using Docker (default)"
    echo "  --bare-metal          Install directly on host system"
    echo "  --services LIST       Comma-separated list of services to install"
    echo "  --category CATEGORY   Install services by category:"
    echo "                         core, ai, analytics, monitoring, workflow, vector, all"
    echo "  --dry-run             Show what would be installed without actually installing"
    echo "  --help                Show this help message"
    echo ""
    echo "Available services:"
    printf "  %s\n" "${AVAILABLE_SERVICES[@]}"
    echo ""
    echo "Available categories:"
    echo "  core        - PostgreSQL, PgVector, Supabase, Qdrant"
    echo "  ai          - OpenWebUI, LocalAI, Flowise, Langfuse, AI Orchestrator"
    echo "  analytics   - ClickHouse, OpenSearch"
    echo "  monitoring  - Prometheus, Grafana, Loki, Sentry"
    echo "  workflow    - N8N"
    echo "  vector      - Qdrant, Weaviate"
    echo "  all         - All available services"
    echo ""
    echo "Examples:"
    echo "  $0 --category core                    # Install core services"
    echo "  $0 --services postgresql,qdrant      # Install specific services"
    echo "  $0 --dry-run                         # Preview installation"
    exit 1
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

check_dependencies() {
    log "Checking dependencies..."
    
    if [[ "$INSTALL_TYPE" == "docker" ]]; then
        if ! command -v docker &> /dev/null; then
            error "Docker is not installed. Please install Docker first."
            exit 1
        fi
        
        if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
            error "Docker Compose is not available. Please install Docker Compose."
            exit 1
        fi
    fi
    
    # Check if required tools are available
    for tool in curl git; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install $tool first."
            exit 1
        fi
    done
    
    log "Dependencies check passed"
}

expand_services() {
    local input="$1"
    local services=()
    
    case "$input" in
        "all")
            services=("${AVAILABLE_SERVICES[@]}")
            ;;
        "core")
            services=("${CORE_SERVICES[@]}")
            ;;
        "ai")
            services=("${AI_SERVICES[@]}")
            ;;
        "analytics")
            services=("${ANALYTICS_SERVICES[@]}")
            ;;
        "monitoring")
            services=("${MONITORING_SERVICES[@]}")
            ;;
        "workflow")
            services=("${WORKFLOW_SERVICES[@]}")
            ;;
        "vector")
            services=("${VECTOR_SERVICES[@]}")
            ;;
        *)
            # Parse comma-separated list
            IFS=',' read -ra services <<< "$input"
            ;;
    esac
    
    printf "%s\n" "${services[@]}"
}

validate_services() {
    local services=("$@")
    local invalid_services=()
    
    for service in "${services[@]}"; do
        if [[ ! " ${AVAILABLE_SERVICES[*]} " =~ " ${service} " ]]; then
            invalid_services+=("$service")
        fi
    done
    
    if [[ ${#invalid_services[@]} -gt 0 ]]; then
        error "Invalid services: ${invalid_services[*]}"
        echo "Available services: ${AVAILABLE_SERVICES[*]}"
        exit 1
    fi
}

install_service() {
    local service="$1"
    local script_path="$SCRIPT_DIR/${service}.sh"
    
    log "Installing $service..."
    
    # Handle special cases for services with different script names
    case "$service" in
        "postgresql"|"pgvector")
            # These are handled by supabase installation
            if [[ "$service" == "postgresql" || "$service" == "pgvector" ]]; then
                log "$service is included in Supabase installation"
                return 0
            fi
            ;;
        "openwebui"|"localai"|"flowise"|"langfuse"|"n8n")
            # These are already configured in existing docker-compose files
            log "$service is already configured in the stack"
            return 0
            ;;
        "prometheus")
            # Prometheus is already configured
            log "$service is already configured in monitoring stack"
            return 0
            ;;
    esac
    
    # Check if installation script exists
    if [[ ! -f "$script_path" ]]; then
        error "Installation script not found: $script_path"
        return 1
    fi
    
    # Make script executable
    chmod +x "$script_path"
    
    # Run installation script
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would execute: $script_path --$INSTALL_TYPE"
    else
        if "$script_path" "--$INSTALL_TYPE"; then
            log "✅ $service installed successfully"
        else
            error "❌ Failed to install $service"
            return 1
        fi
    fi
}

create_unified_compose() {
    local services=("$@")
    local compose_file="$PROJECT_ROOT/docker-compose.unified.yml"
    
    log "Creating unified docker-compose configuration..."
    
    cat > "$compose_file" <<EOF
version: '3.8'

# Unified Docker Compose for Agentic RAG Full Stack
# Generated by install_all.sh

services:
EOF
    
    # Add services based on what's being installed
    for service in "${services[@]}"; do
        case "$service" in
            "weaviate")
                cat >> "$compose_file" <<EOF
  # Weaviate Vector Database
  weaviate:
    image: semitechnologies/weaviate:1.25.5
    ports:
      - "8080:8080"
      - "50051:50051"
    volumes:
      - weaviate_data:/var/lib/weaviate
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      DEFAULT_VECTORIZER_MODULE: 'none'
      ENABLE_MODULES: 'text2vec-openai,text2vec-cohere,text2vec-huggingface'
    restart: unless-stopped

EOF
                ;;
            "clickhouse")
                cat >> "$compose_file" <<EOF
  # ClickHouse Analytics Database
  clickhouse:
    image: clickhouse/clickhouse-server:24.3
    ports:
      - "8123:8123"
      - "9000:9000"
    volumes:
      - clickhouse_data:/var/lib/clickhouse
    restart: unless-stopped
    ulimits:
      nofile:
        soft: 262144
        hard: 262144

EOF
                ;;
            "grafana")
                cat >> "$compose_file" <<EOF
  # Grafana Monitoring Dashboard
  grafana:
    image: grafana/grafana:10.2.2
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    restart: unless-stopped

EOF
                ;;
        esac
    done
    
    # Add volumes section
    cat >> "$compose_file" <<EOF

volumes:
EOF
    
    for service in "${services[@]}"; do
        case "$service" in
            "weaviate")
                echo "  weaviate_data:" >> "$compose_file"
                ;;
            "clickhouse")
                echo "  clickhouse_data:" >> "$compose_file"
                ;;
            "grafana")
                echo "  grafana_data:" >> "$compose_file"
                ;;
        esac
    done
    
    log "Unified compose file created: $compose_file"
}

generate_startup_script() {
    local services=("$@")
    local startup_script="$PROJECT_ROOT/start_all_services.sh"
    
    log "Generating startup script..."
    
    cat > "$startup_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Auto-generated startup script for all installed services
# This script starts all services in the correct order

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting all services..."

# Start core infrastructure first
if [[ -f "$SCRIPT_DIR/docker-compose.supabase.yml" ]]; then
    log "Starting Supabase stack..."
    docker compose -f "$SCRIPT_DIR/docker-compose.supabase.yml" up -d
fi

# Start monitoring services
if [[ -f "$SCRIPT_DIR/docker-compose.monitoring.yml" ]]; then
    log "Starting monitoring stack..."
    docker compose -f "$SCRIPT_DIR/docker-compose.monitoring.yml" up -d
fi

# Start additional services
EOF
    
    for service in "${services[@]}"; do
        case "$service" in
            "weaviate"|"clickhouse"|"opensearch"|"grafana"|"loki"|"sentry"|"ai-orchestrator")
                cat >> "$startup_script" <<EOF

if [[ -f "\$SCRIPT_DIR/docker-compose.${service}.yml" ]]; then
    log "Starting ${service}..."
    docker compose -f "\$SCRIPT_DIR/docker-compose.${service}.yml" up -d
fi
EOF
                ;;
        esac
    done
    
    cat >> "$startup_script" <<'EOF'

# Start main application stack
if [[ -f "$SCRIPT_DIR/docker/docker-compose.stack.yml" ]]; then
    log "Starting main application stack..."
    docker compose -f "$SCRIPT_DIR/docker/docker-compose.stack.yml" up -d
fi

log "All services started!"
log "Use 'docker ps' to check running containers"

echo ""
echo "🚀 Agentic RAG Full Stack is now running!"
echo ""
echo "📊 Available Services:"
echo "   - Supabase Studio: http://localhost:54330"
echo "   - OpenWebUI: http://localhost:3002"
echo "   - Langfuse: http://localhost:3003"
echo "   - Flowise: http://localhost:3004"
echo "   - N8N: http://localhost:5678"
echo "   - Grafana: http://localhost:3000"
echo "   - Prometheus: http://localhost:9090"
EOF
    
    for service in "${services[@]}"; do
        case "$service" in
            "weaviate")
                echo "   - Weaviate: http://localhost:8080" >> "$startup_script"
                ;;
            "clickhouse")
                echo "   - ClickHouse: http://localhost:8123" >> "$startup_script"
                ;;
            "opensearch")
                echo "   - OpenSearch: http://localhost:9200" >> "$startup_script"
                echo "   - OpenSearch Dashboards: http://localhost:5601" >> "$startup_script"
                ;;
            "sentry")
                echo "   - Sentry: http://localhost:9000" >> "$startup_script"
                ;;
            "ai-orchestrator")
                echo "   - AI Orchestrator: http://localhost:8090" >> "$startup_script"
                ;;
        esac
    done
    
    chmod +x "$startup_script"
    log "Startup script created: $startup_script"
}

# Parse arguments
while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --services) SERVICES_TO_INSTALL="$2"; shift 2 ;;
        --category) SERVICES_TO_INSTALL="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Main execution
main() {
    log "🚀 Starting Agentic RAG Full Stack Installation"
    log "Installation type: $INSTALL_TYPE"
    log "Services to install: $SERVICES_TO_INSTALL"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No actual installation will be performed"
    fi
    
    # Check dependencies
    check_dependencies
    
    # Expand and validate services
    readarray -t services_list < <(expand_services "$SERVICES_TO_INSTALL")
    validate_services "${services_list[@]}"
    
    log "Will install ${#services_list[@]} services: ${services_list[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run completed. No changes were made."
        return 0
    fi
    
    # Create environment file if it doesn't exist
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log "Creating environment configuration..."
        "$PROJECT_ROOT/scripts/create_envs.sh"
    fi
    
    # Install services
    local failed_services=()
    for service in "${services_list[@]}"; do
        if ! install_service "$service"; then
            failed_services+=("$service")
        fi
    done
    
    # Report results
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        error "Failed to install: ${failed_services[*]}"
        echo "Successfully installed: $(comm -23 <(printf "%s\n" "${services_list[@]}" | sort) <(printf "%s\n" "${failed_services[@]}" | sort) | tr '\n' ' ')"
        exit 1
    fi
    
    # Generate startup utilities
    generate_startup_script "${services_list[@]}"
    
    log "✅ Installation completed successfully!"
    log "📚 To start all services, run: ./start_all_services.sh"
    log "📊 Visit the service URLs to access the web interfaces"
}

# Run main function
main "$@"