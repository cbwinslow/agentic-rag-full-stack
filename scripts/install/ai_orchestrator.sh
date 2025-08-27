#!/usr/bin/env bash
set -euo pipefail

# scripts/install/ai_orchestrator.sh
# Install AI Orchestrator Agent (LocalAI + Ollama + OpenRouter integration)
# This agent oversees and deploys smaller agents for various tasks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
LOCALAI_VERSION="${LOCALAI_VERSION:-v2.5.0}"
OLLAMA_VERSION="${OLLAMA_VERSION:-latest}"
ORCHESTRATOR_PORT="${ORCHESTRATOR_PORT:-8090}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
AI_DATA_DIR="${PROJECT_ROOT}/data/ai-orchestrator"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--port PORT] [--data-dir DIR]"
    echo "  --docker       Install using Docker (default)"
    echo "  --bare-metal   Install directly on host system"
    echo "  --port PORT    Set orchestrator port (default: 8090)"
    echo "  --data-dir     Set data directory (default: ./data/ai-orchestrator)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --port) ORCHESTRATOR_PORT="$2"; shift 2 ;;
        --data-dir) AI_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing AI Orchestrator Agent..."
echo "Installation type: $INSTALL_TYPE"
echo "Port: $ORCHESTRATOR_PORT"
echo "Data directory: $AI_DATA_DIR"

# Create data directory
mkdir -p "$AI_DATA_DIR"/{models,agents,configs,logs}

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing AI Orchestrator using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Create orchestrator configuration
    cat > "$AI_DATA_DIR/configs/orchestrator.yml" <<EOF
orchestrator:
  name: "AI Task Orchestrator"
  version: "1.0.0"
  port: ${ORCHESTRATOR_PORT}
  
  # AI Providers Configuration
  providers:
    localai:
      enabled: true
      url: "http://localai:8080"
      models:
        - "gpt-3.5-turbo"
        - "llama2"
        - "codellama"
    
    ollama:
      enabled: true
      url: "http://ollama:11434"
      models:
        - "llama2"
        - "mistral"
        - "codellama"
    
    openrouter:
      enabled: false
      url: "https://openrouter.ai/api/v1"
      api_key: "\${OPENROUTER_API_KEY}"
      models:
        - "anthropic/claude-3-sonnet"
        - "openai/gpt-4"

  # Agent Types and Capabilities
  agent_types:
    data_processor:
      description: "Processes and analyzes data"
      capabilities: ["data_cleaning", "feature_extraction", "analysis"]
      preferred_models: ["gpt-3.5-turbo", "llama2"]
    
    code_generator:
      description: "Generates and reviews code"
      capabilities: ["code_generation", "code_review", "debugging"]
      preferred_models: ["codellama", "gpt-4"]
    
    content_creator:
      description: "Creates various types of content"
      capabilities: ["text_generation", "summarization", "translation"]
      preferred_models: ["gpt-3.5-turbo", "claude-3-sonnet"]
    
    monitoring_agent:
      description: "Monitors system health and performance"
      capabilities: ["log_analysis", "anomaly_detection", "alerting"]
      preferred_models: ["llama2", "mistral"]

  # Task Queue Configuration
  task_queue:
    type: "redis"
    url: "redis://redis:6379"
    max_retries: 3
    timeout: 300

  # Monitoring and Logging
  monitoring:
    enabled: true
    prometheus_endpoint: "http://prometheus:9090"
    grafana_endpoint: "http://grafana:3000"
    
  logging:
    level: "info"
    format: "json"
    output: "/var/log/orchestrator.log"
EOF

    # Create orchestrator Python application
    cat > "$AI_DATA_DIR/orchestrator.py" <<'EOF'
#!/usr/bin/env python3
"""
AI Task Orchestrator
Manages and deploys specialized AI agents for various tasks
"""

import asyncio
import json
import logging
import yaml
from typing import Dict, List, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx
import redis
from datetime import datetime

# Load configuration
with open('/app/configs/orchestrator.yml', 'r') as f:
    config = yaml.safe_load(f)

app = FastAPI(title="AI Task Orchestrator", version="1.0.0")
redis_client = redis.Redis.from_url(config['orchestrator']['task_queue']['url'])

class TaskRequest(BaseModel):
    task_type: str
    agent_type: str
    prompt: str
    model_preference: Optional[str] = None
    priority: int = 1

class AgentResponse(BaseModel):
    task_id: str
    agent_type: str
    model_used: str
    response: str
    execution_time: float
    status: str

class AIOrchestrator:
    def __init__(self):
        self.providers = config['orchestrator']['providers']
        self.agent_types = config['orchestrator']['agent_types']
        self.active_agents = {}
        
    async def select_best_provider(self, agent_type: str, model_preference: str = None) -> Dict:
        """Select the best AI provider and model for the given task"""
        agent_config = self.agent_types.get(agent_type, {})
        preferred_models = agent_config.get('preferred_models', [])
        
        if model_preference and model_preference in preferred_models:
            # Find provider that has this model
            for provider_name, provider_config in self.providers.items():
                if provider_config['enabled'] and model_preference in provider_config['models']:
                    return {
                        'provider': provider_name,
                        'model': model_preference,
                        'url': provider_config['url']
                    }
        
        # Fallback to first available provider with preferred model
        for model in preferred_models:
            for provider_name, provider_config in self.providers.items():
                if provider_config['enabled'] and model in provider_config['models']:
                    return {
                        'provider': provider_name,
                        'model': model,
                        'url': provider_config['url']
                    }
        
        # Last resort: any available provider
        for provider_name, provider_config in self.providers.items():
            if provider_config['enabled'] and provider_config['models']:
                return {
                    'provider': provider_name,
                    'model': provider_config['models'][0],
                    'url': provider_config['url']
                }
        
        raise HTTPException(status_code=503, detail="No AI providers available")
    
    async def execute_task(self, task: TaskRequest) -> AgentResponse:
        """Execute a task using the most appropriate AI agent"""
        start_time = datetime.now()
        task_id = f"{task.agent_type}_{int(start_time.timestamp())}"
        
        try:
            # Select best provider
            provider_info = await self.select_best_provider(task.agent_type, task.model_preference)
            
            # Prepare prompt based on agent type
            agent_config = self.agent_types.get(task.agent_type, {})
            system_prompt = f"You are a {agent_config.get('description', 'helpful AI assistant')}. "
            system_prompt += f"Your capabilities include: {', '.join(agent_config.get('capabilities', []))}."
            
            # Make API call to selected provider
            async with httpx.AsyncClient() as client:
                if provider_info['provider'] in ['localai', 'ollama']:
                    # OpenAI-compatible API
                    response = await client.post(
                        f"{provider_info['url']}/v1/chat/completions",
                        json={
                            "model": provider_info['model'],
                            "messages": [
                                {"role": "system", "content": system_prompt},
                                {"role": "user", "content": task.prompt}
                            ],
                            "temperature": 0.7,
                            "max_tokens": 2000
                        },
                        timeout=120
                    )
                    response.raise_for_status()
                    result = response.json()
                    ai_response = result['choices'][0]['message']['content']
                
                elif provider_info['provider'] == 'openrouter':
                    # OpenRouter API
                    headers = {
                        "Authorization": f"Bearer {config['orchestrator']['providers']['openrouter']['api_key']}",
                        "Content-Type": "application/json"
                    }
                    response = await client.post(
                        f"{provider_info['url']}/chat/completions",
                        headers=headers,
                        json={
                            "model": provider_info['model'],
                            "messages": [
                                {"role": "system", "content": system_prompt},
                                {"role": "user", "content": task.prompt}
                            ]
                        },
                        timeout=120
                    )
                    response.raise_for_status()
                    result = response.json()
                    ai_response = result['choices'][0]['message']['content']
                
                else:
                    raise HTTPException(status_code=500, detail=f"Unknown provider: {provider_info['provider']}")
            
            execution_time = (datetime.now() - start_time).total_seconds()
            
            return AgentResponse(
                task_id=task_id,
                agent_type=task.agent_type,
                model_used=f"{provider_info['provider']}/{provider_info['model']}",
                response=ai_response,
                execution_time=execution_time,
                status="completed"
            )
            
        except Exception as e:
            execution_time = (datetime.now() - start_time).total_seconds()
            logging.error(f"Task {task_id} failed: {str(e)}")
            
            return AgentResponse(
                task_id=task_id,
                agent_type=task.agent_type,
                model_used="error",
                response=f"Task failed: {str(e)}",
                execution_time=execution_time,
                status="failed"
            )

orchestrator = AIOrchestrator()

@app.get("/")
async def root():
    return {"message": "AI Task Orchestrator", "version": "1.0.0"}

@app.get("/health")
async def health():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.get("/providers")
async def list_providers():
    """List available AI providers and their models"""
    return config['orchestrator']['providers']

@app.get("/agent-types")
async def list_agent_types():
    """List available agent types and their capabilities"""
    return config['orchestrator']['agent_types']

@app.post("/execute", response_model=AgentResponse)
async def execute_task(task: TaskRequest):
    """Execute a task using the most appropriate AI agent"""
    return await orchestrator.execute_task(task)

@app.post("/deploy-agent")
async def deploy_agent(agent_type: str, instance_count: int = 1):
    """Deploy specialized agent instances for handling specific tasks"""
    # This would deploy containerized agents for specific tasks
    # For now, return a placeholder response
    return {
        "message": f"Deployed {instance_count} instances of {agent_type} agent",
        "agent_type": agent_type,
        "instances": instance_count
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(config['orchestrator']['port']))
EOF

    # Create Dockerfile for orchestrator
    cat > "$AI_DATA_DIR/Dockerfile" <<'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN pip install fastapi uvicorn httpx redis pyyaml

COPY configs/ /app/configs/
COPY orchestrator.py /app/

EXPOSE 8090

CMD ["python", "orchestrator.py"]
EOF

    # Create docker-compose configuration
    cat > "$PROJECT_ROOT/docker-compose.ai-orchestrator.yml" <<EOF
version: '3.8'
services:
  localai:
    image: localai/localai:${LOCALAI_VERSION}
    ports:
      - "8080:8080"
    volumes:
      - ai_models:/models
    environment:
      - GALLERIES='[{"name":"model-gallery", "url":"github:go-skynet/model-gallery/index.yaml"}]'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/readiness"]
      interval: 30s
      timeout: 10s
      retries: 5

  ollama:
    image: ollama/ollama:${OLLAMA_VERSION}
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/version"]
      interval: 30s
      timeout: 10s
      retries: 5

  ai-orchestrator:
    build:
      context: ${AI_DATA_DIR}
      dockerfile: Dockerfile
    ports:
      - "${ORCHESTRATOR_PORT}:8090"
    depends_on:
      localai:
        condition: service_healthy
      ollama:
        condition: service_healthy
      redis:
        condition: service_started
    environment:
      - OPENROUTER_API_KEY=\${OPENROUTER_API_KEY:-}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
      interval: 30s
      timeout: 10s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 5

volumes:
  ai_models:
  ollama_data:
  redis_data:
EOF
    
    echo "Building and starting AI Orchestrator..."
    docker compose -f "$PROJECT_ROOT/docker-compose.ai-orchestrator.yml" up -d --build
    
    echo "Waiting for services to be ready..."
    sleep 30
    
    # Download initial models
    echo "Setting up initial AI models..."
    docker compose -f "$PROJECT_ROOT/docker-compose.ai-orchestrator.yml" exec -T ollama ollama pull llama2 || true
    docker compose -f "$PROJECT_ROOT/docker-compose.ai-orchestrator.yml" exec -T ollama ollama pull mistral || true
    
    # Wait for orchestrator to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$ORCHESTRATOR_PORT/health" &>/dev/null; then
            echo "AI Orchestrator is ready!"
            break
        fi
        echo "Waiting for AI Orchestrator... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: AI Orchestrator failed to start within expected time"
        exit 1
    fi
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Bare metal installation for AI Orchestrator is complex and requires manual setup."
    echo "Please use Docker installation for easier deployment."
    exit 1
fi

# Test installation
echo "Testing AI Orchestrator installation..."
sleep 5

if curl -f "http://localhost:$ORCHESTRATOR_PORT/health" &>/dev/null; then
    echo "✅ AI Orchestrator is running successfully!"
    echo "🤖 Orchestrator API: http://localhost:$ORCHESTRATOR_PORT"
    echo "🧠 LocalAI: http://localhost:8080"
    echo "🦙 Ollama: http://localhost:11434"
    echo ""
    echo "Available endpoints:"
    echo "  - GET  /providers - List AI providers"
    echo "  - GET  /agent-types - List agent types"
    echo "  - POST /execute - Execute tasks"
    echo "  - POST /deploy-agent - Deploy specialized agents"
    echo ""
    echo "Example usage:"
    echo "curl -X POST http://localhost:$ORCHESTRATOR_PORT/execute \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"task_type\": \"analysis\", \"agent_type\": \"data_processor\", \"prompt\": \"Analyze this data: [1,2,3,4,5]\"}'"
else
    echo "❌ Error: AI Orchestrator is not responding"
    exit 1
fi

echo "AI Orchestrator installation completed successfully!"