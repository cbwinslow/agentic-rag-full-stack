#!/usr/bin/env bash
set -euo pipefail

# scripts/install/clickhouse.sh
# Install ClickHouse OLAP database for analytics and real-time processing
# Supports both Docker and bare metal installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
CLICKHOUSE_VERSION="${CLICKHOUSE_VERSION:-24.3}"
CLICKHOUSE_HTTP_PORT="${CLICKHOUSE_HTTP_PORT:-8123}"
CLICKHOUSE_TCP_PORT="${CLICKHOUSE_TCP_PORT:-9000}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
CLICKHOUSE_DATA_DIR="${PROJECT_ROOT}/data/clickhouse"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--http-port PORT] [--tcp-port PORT] [--data-dir DIR]"
    echo "  --docker       Install using Docker (default)"
    echo "  --bare-metal   Install directly on host system"
    echo "  --http-port    Set HTTP port (default: 8123)"
    echo "  --tcp-port     Set TCP port (default: 9000)"
    echo "  --data-dir     Set data directory (default: ./data/clickhouse)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --http-port) CLICKHOUSE_HTTP_PORT="$2"; shift 2 ;;
        --tcp-port) CLICKHOUSE_TCP_PORT="$2"; shift 2 ;;
        --data-dir) CLICKHOUSE_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing ClickHouse OLAP database..."
echo "Installation type: $INSTALL_TYPE"
echo "HTTP Port: $CLICKHOUSE_HTTP_PORT"
echo "TCP Port: $CLICKHOUSE_TCP_PORT"
echo "Data directory: $CLICKHOUSE_DATA_DIR"

# Create data directory
mkdir -p "$CLICKHOUSE_DATA_DIR"

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing ClickHouse using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Create ClickHouse configuration
    mkdir -p "$CLICKHOUSE_DATA_DIR/config"
    cat > "$CLICKHOUSE_DATA_DIR/config/config.xml" <<EOF
<?xml version="1.0"?>
<clickhouse>
    <logger>
        <level>information</level>
        <console>true</console>
    </logger>
    
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    
    <openSSL>
        <server>
            <certificateFile>/etc/ssl/certs/ssl-cert-snakeoil.pem</certificateFile>
            <privateKeyFile>/etc/ssl/private/ssl-cert-snakeoil.key</privateKeyFile>
            <dhParamsFile>/etc/ssl/certs/dhparam.pem</dhParamsFile>
            <verificationMode>none</verificationMode>
            <loadDefaultCAFile>true</loadDefaultCAFile>
            <cacheSessions>true</cacheSessions>
            <disableProtocols>sslv2,sslv3</disableProtocols>
            <preferServerCiphers>true</preferServerCiphers>
        </server>
        <client>
            <loadDefaultCAFile>true</loadDefaultCAFile>
            <cacheSessions>true</cacheSessions>
            <disableProtocols>sslv2,sslv3</disableProtocols>
            <preferServerCiphers>true</preferServerCiphers>
            <verificationMode>none</verificationMode>
            <invalidCertificateHandler>
                <name>AcceptCertificateHandler</name>
            </invalidCertificateHandler>
        </client>
    </openSSL>
    
    <max_connections>2048</max_connections>
    <keep_alive_timeout>3</keep_alive_timeout>
    <max_concurrent_queries>1000</max_concurrent_queries>
    <uncompressed_cache_size>8589934592</uncompressed_cache_size>
    <mark_cache_size>5368709120</mark_cache_size>
    
    <path>/var/lib/clickhouse/</path>
    <tmp_path>/var/lib/clickhouse/tmp/</tmp_path>
    <user_files_path>/var/lib/clickhouse/user_files/</user_files_path>
    <access_control_path>/var/lib/clickhouse/access/</access_control_path>
    <format_schema_path>/var/lib/clickhouse/format_schemas/</format_schema_path>
    
    <users_config>users.xml</users_config>
    <default_profile>default</default_profile>
    <default_database>default</default_database>
    
    <timezone>UTC</timezone>
</clickhouse>
EOF

    cat > "$CLICKHOUSE_DATA_DIR/config/users.xml" <<EOF
<?xml version="1.0"?>
<clickhouse>
    <users>
        <default>
            <password></password>
            <networks incl="networks" replace="replace">
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
        </default>
    </users>
    
    <profiles>
        <default>
            <max_memory_usage>10000000000</max_memory_usage>
            <use_uncompressed_cache>0</use_uncompressed_cache>
            <load_balancing>random</load_balancing>
        </default>
    </profiles>
    
    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</clickhouse>
EOF
    
    # Create docker-compose configuration for ClickHouse
    cat > "$PROJECT_ROOT/docker-compose.clickhouse.yml" <<EOF
version: '3.8'
services:
  clickhouse:
    image: clickhouse/clickhouse-server:${CLICKHOUSE_VERSION}
    ports:
      - "${CLICKHOUSE_HTTP_PORT}:8123"
      - "${CLICKHOUSE_TCP_PORT}:9000"
    volumes:
      - clickhouse_data:/var/lib/clickhouse
      - ${CLICKHOUSE_DATA_DIR}/config/config.xml:/etc/clickhouse-server/config.xml:ro
      - ${CLICKHOUSE_DATA_DIR}/config/users.xml:/etc/clickhouse-server/users.xml:ro
    restart: unless-stopped
    environment:
      CLICKHOUSE_DB: analytics
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8123/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    ulimits:
      nofile:
        soft: 262144
        hard: 262144

volumes:
  clickhouse_data:
EOF
    
    echo "Starting ClickHouse container..."
    docker compose -f "$PROJECT_ROOT/docker-compose.clickhouse.yml" up -d
    
    echo "Waiting for ClickHouse to be ready..."
    sleep 10
    
    # Wait for ClickHouse to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$CLICKHOUSE_HTTP_PORT/ping" &>/dev/null; then
            echo "ClickHouse is ready!"
            break
        fi
        echo "Waiting for ClickHouse... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: ClickHouse failed to start within expected time"
        exit 1
    fi
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Installing ClickHouse on bare metal..."
    
    # Detect OS and install ClickHouse
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Install on Linux
        if command -v apt-get &> /dev/null; then
            # Ubuntu/Debian
            echo "Installing ClickHouse on Ubuntu/Debian..."
            curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | sudo gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | sudo tee /etc/apt/sources.list.d/clickhouse.list
            sudo apt-get update
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y clickhouse-server clickhouse-client
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS
            echo "Installing ClickHouse on RHEL/CentOS..."
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://packages.clickhouse.com/rpm/clickhouse.repo
            sudo yum install -y clickhouse-server clickhouse-client
        else
            echo "Error: Unsupported Linux distribution"
            exit 1
        fi
        
        # Configure ClickHouse
        sudo mkdir -p /etc/clickhouse-server/config.d
        echo "<yandex><listen_host>::</listen_host></yandex>" | sudo tee /etc/clickhouse-server/config.d/listen.xml
        
        # Start ClickHouse service
        sudo systemctl enable clickhouse-server
        sudo systemctl start clickhouse-server
        
        echo "ClickHouse service started. Use 'sudo systemctl status clickhouse-server' to check status."
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Install on macOS
        echo "Installing ClickHouse on macOS..."
        if command -v brew &> /dev/null; then
            brew install clickhouse
            brew services start clickhouse
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
echo "Testing ClickHouse installation..."
sleep 5

if curl -f "http://localhost:$CLICKHOUSE_HTTP_PORT/ping" &>/dev/null; then
    echo "✅ ClickHouse is running successfully!"
    echo "📊 HTTP Interface: http://localhost:$CLICKHOUSE_HTTP_PORT"
    echo "🔌 TCP Port: $CLICKHOUSE_TCP_PORT"
    echo ""
    echo "Example usage:"
    echo "echo 'SELECT version()' | curl 'http://localhost:$CLICKHOUSE_HTTP_PORT/' --data-binary @-"
    echo "clickhouse-client --query 'SELECT version()'"
else
    echo "❌ Error: ClickHouse is not responding"
    exit 1
fi

echo "ClickHouse installation completed successfully!"