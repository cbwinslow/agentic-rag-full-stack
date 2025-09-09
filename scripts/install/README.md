# Installation Scripts

This directory contains individual installation scripts for all services in the Agentic RAG Full Stack platform. Each script supports both Docker and bare metal installations.

## Quick Start

### Install All Services
```bash
# Install all services using Docker (recommended)
./scripts/install/install_all.sh

# Install specific category
./scripts/install/install_all.sh --category ai

# Install specific services
./scripts/install/install_all.sh --services weaviate,clickhouse,grafana

# Preview what would be installed
./scripts/install/install_all.sh --dry-run
```

### Individual Service Installation
```bash
# Install specific service
./scripts/install/weaviate.sh --docker --port 8080
./scripts/install/clickhouse.sh --bare-metal
./scripts/install/opensearch.sh --docker
```

## Available Scripts

### Core Services
- `postgresql` - PostgreSQL database (included in Supabase)
- `pgvector` - Vector extension for PostgreSQL 
- `supabase.sh` - Complete Supabase stack (use existing script)
- `qdrant` - Vector database (already configured)

### Vector Databases
- `weaviate.sh` - Weaviate vector database
- `qdrant` - Qdrant vector database (already configured)

### Analytics & Search
- `clickhouse.sh` - ClickHouse OLAP database
- `opensearch.sh` - OpenSearch with Dashboards

### AI & ML Services  
- `openwebui` - Open WebUI (already configured)
- `localai` - LocalAI (already configured)
- `local_ai_packaged.sh` - Enhanced LocalAI with preloaded models
- `flowise` - Flowise low-code AI (already configured)
- `langfuse` - LLM observability (already configured)
- `agentic_rag_knowledge_graph.sh` - Advanced RAG with knowledge graphs
- `ai_orchestrator.sh` - AI agent orchestration system

### Monitoring & Observability
- `prometheus` - Metrics collection (already configured)
- `grafana.sh` - Monitoring dashboards
- `loki.sh` - Log aggregation
- `sentry.sh` - Error tracking and performance monitoring

### Workflow & Automation
- `n8n` - Workflow automation (already configured)

## Service Categories

### Core Infrastructure
Essential services for the platform foundation:
- PostgreSQL with PgVector
- Supabase stack
- Qdrant vector database

### AI & Machine Learning
Services for AI model deployment and management:
- OpenWebUI for chat interfaces
- LocalAI for local model serving
- Flowise for low-code AI workflows
- Langfuse for LLM observability
- AI Orchestrator for agent management

### Analytics & Search
Services for data analysis and search:
- ClickHouse for analytics
- OpenSearch for full-text search and log analysis

### Monitoring & Observability
Services for system monitoring and debugging:
- Prometheus for metrics
- Grafana for dashboards
- Loki for log aggregation
- Sentry for error tracking

### Vector & Knowledge
Advanced vector and knowledge graph services:
- Weaviate for semantic search
- Agentic RAG Knowledge Graph for advanced reasoning

## Installation Options

### Docker Installation (Recommended)
```bash
# Install with Docker (default)
./script_name.sh --docker

# Advantages:
# - Easy setup and management
# - Consistent environments
# - Built-in health checks
# - Easy scaling and updates
```

### Bare Metal Installation
```bash
# Install directly on host system
./script_name.sh --bare-metal

# Advantages:
# - Better performance
# - Direct system integration
# - Custom configurations
# - Resource efficiency
```

## Configuration

### Environment Variables
Services use environment variables for configuration. Create or update `.env`:

```bash
# Generate default environment
./scripts/create_envs.sh

# Key variables:
OPENROUTER_API_KEY=your_api_key_here
SENTRY_DSN=your_sentry_dsn_here
GRAFANA_ADMIN_PASSWORD=secure_password
```

### Port Configuration
Default ports for services:

| Service | Port | Alternative |
|---------|------|-------------|
| Supabase Studio | 54330 | |
| OpenWebUI | 3002 | |
| Langfuse | 3003 | |
| Flowise | 3004 | |
| N8N | 5678 | |
| Grafana | 3000 | |
| Prometheus | 9090 | |
| Weaviate | 8080 | |
| ClickHouse HTTP | 8123 | |
| ClickHouse TCP | 9000 | |
| OpenSearch | 9200 | |
| OpenSearch Dashboards | 5601 | |
| Loki | 3100 | |
| Sentry | 9000 | |
| AI Orchestrator | 8090 | |

### Custom Ports
```bash
# Use custom ports
./scripts/install/grafana.sh --port 3001
./scripts/install/weaviate.sh --port 8081
```

## Service Management

### Starting Services
```bash
# Start all services (generated after installation)
./start_all_services.sh

# Start individual services
docker compose -f docker-compose.grafana.yml up -d
docker compose -f docker-compose.weaviate.yml up -d
```

### Stopping Services
```bash
# Stop all services
docker compose down

# Stop specific service
docker compose -f docker-compose.grafana.yml down
```

### Health Checks
```bash
# Check service health
curl http://localhost:3000/api/health  # Grafana
curl http://localhost:8080/v1/.well-known/ready  # Weaviate
curl http://localhost:8123/ping  # ClickHouse
```

## Troubleshooting

### Common Issues

1. **Port Conflicts**
   ```bash
   # Check port usage
   netstat -tulpn | grep :3000
   
   # Use alternative port
   ./script.sh --port 3001
   ```

2. **Docker Issues**
   ```bash
   # Check Docker status
   docker --version
   docker compose version
   
   # Restart Docker service
   sudo systemctl restart docker
   ```

3. **Permission Issues**
   ```bash
   # Fix script permissions
   chmod +x scripts/install/*.sh
   
   # Fix data directory permissions
   sudo chown -R $USER:$USER data/
   ```

4. **Memory Issues**
   ```bash
   # Check available memory
   free -h
   
   # Increase Docker memory limits
   # Edit ~/.docker/daemon.json
   ```

### Log Analysis
```bash
# View service logs
docker compose logs -f service_name

# View installation logs
tail -f /var/log/install.log
```

## Development

### Adding New Services

1. Create new installation script:
   ```bash
   cp scripts/install/template.sh scripts/install/new_service.sh
   ```

2. Update the script with service-specific configuration

3. Add to `install_all.sh`:
   ```bash
   # Add to AVAILABLE_SERVICES array
   AVAILABLE_SERVICES+=("new_service")
   ```

4. Test the installation:
   ```bash
   ./scripts/install/new_service.sh --dry-run
   ```

### Script Template
Use this template for new installation scripts:

```bash
#!/usr/bin/env bash
set -euo pipefail

# scripts/install/service_name.sh
# Install SERVICE_NAME with description
# Supports both Docker and bare metal installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
SERVICE_VERSION="${SERVICE_VERSION:-latest}"
SERVICE_PORT="${SERVICE_PORT:-8080}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
SERVICE_DATA_DIR="${PROJECT_ROOT}/data/service_name"

# Add your installation logic here
```

## Security Considerations

### Default Credentials
Change default passwords after installation:

- Grafana: admin/admin
- Sentry: admin@example.com/admin  
- OpenSearch: admin/admin

### Network Security
```bash
# Bind services to localhost only
docker compose up -d --env-file .env.local

# Use SSL certificates in production
# Configure firewall rules
# Enable authentication
```

### Data Protection
```bash
# Backup data directories
tar -czf backup.tar.gz data/

# Use encrypted volumes
# Set proper file permissions
# Regular security updates
```

## Production Deployment

### Scaling Considerations
- Use Docker Swarm or Kubernetes for orchestration
- Configure load balancers
- Set up monitoring and alerting
- Implement backup strategies
- Use managed databases for production

### Performance Tuning
- Allocate sufficient memory and CPU
- Configure connection pooling
- Optimize database settings
- Use caching where appropriate
- Monitor resource usage

## Support

### Getting Help
1. Check service-specific documentation
2. Review Docker logs for errors
3. Verify network connectivity
4. Check resource usage
5. Consult community forums

### Contributing
1. Fork the repository
2. Create feature branch
3. Add/modify installation scripts
4. Test thoroughly
5. Submit pull request

## License

This project is licensed under the MIT License. See individual service licenses for their respective terms.