#!/usr/bin/env bash
set -euo pipefail

# scripts/install/agentic_rag_knowledge_graph.sh
# Install agentic-rag-knowledge-graph from GitHub repo
# Advanced RAG system with knowledge graph capabilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
REPO_URL="${REPO_URL:-https://github.com/agentic-knowledge-rag/graph.git}"
RAG_GRAPH_PORT="${RAG_GRAPH_PORT:-7000}"
INSTALL_TYPE="${INSTALL_TYPE:-docker}"
RAG_GRAPH_DATA_DIR="${PROJECT_ROOT}/data/agentic-rag-knowledge-graph"

usage() {
    echo "Usage: $0 [--docker|--bare-metal] [--port PORT] [--repo URL] [--data-dir DIR]"
    echo "  --docker       Install using Docker (default)"
    echo "  --bare-metal   Install from source"
    echo "  --port PORT    Set service port (default: 7000)"
    echo "  --repo URL     GitHub repository URL"
    echo "  --data-dir     Set data directory (default: ./data/agentic-rag-knowledge-graph)"
    exit 1
}

while [[ ${1:-} != "" ]]; do
    case "$1" in
        --docker) INSTALL_TYPE="docker"; shift ;;
        --bare-metal) INSTALL_TYPE="bare-metal"; shift ;;
        --port) RAG_GRAPH_PORT="$2"; shift 2 ;;
        --repo) REPO_URL="$2"; shift 2 ;;
        --data-dir) RAG_GRAPH_DATA_DIR="$2"; shift 2 ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "Installing Agentic RAG Knowledge Graph..."
echo "Installation type: $INSTALL_TYPE"
echo "Port: $RAG_GRAPH_PORT"
echo "Repository: $REPO_URL"
echo "Data directory: $RAG_GRAPH_DATA_DIR"

# Create data directory
mkdir -p "$RAG_GRAPH_DATA_DIR"/{data,models,configs,logs}

if [[ "$INSTALL_TYPE" == "docker" ]]; then
    echo "Installing Agentic RAG Knowledge Graph using Docker..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker or use --bare-metal option."
        exit 1
    fi
    
    # Clone or update repository if URL is provided and it's a real repo
    if [[ "$REPO_URL" != *"placeholder"* ]] && curl -s --head "$REPO_URL" | head -n 1 | grep -q "200 OK"; then
        if [ ! -d "$RAG_GRAPH_DATA_DIR/source" ]; then
            echo "Cloning repository..."
            git clone "$REPO_URL" "$RAG_GRAPH_DATA_DIR/source"
        else
            echo "Updating repository..."
            cd "$RAG_GRAPH_DATA_DIR/source"
            git pull
        fi
    else
        echo "Repository not available, creating local implementation..."
        mkdir -p "$RAG_GRAPH_DATA_DIR/source"
    fi
    
    # Create local implementation if repository doesn't exist
    if [ ! -f "$RAG_GRAPH_DATA_DIR/source/app.py" ]; then
        echo "Creating local Agentic RAG Knowledge Graph implementation..."
        
        # Create main application
        cat > "$RAG_GRAPH_DATA_DIR/source/app.py" <<'EOF'
#!/usr/bin/env python3
"""
Agentic RAG Knowledge Graph
Advanced RAG system with knowledge graph capabilities and agentic behavior
"""

import asyncio
import json
import logging
from typing import Dict, List, Optional, Any
from datetime import datetime
import uuid

from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
import uvicorn
import networkx as nx
import numpy as np
from sentence_transformers import SentenceTransformer
import sqlite3
import os

# Configuration
DATABASE_PATH = "/app/data/knowledge_graph.db"
VECTOR_MODEL = "all-MiniLM-L6-v2"
EMBEDDING_DIMENSION = 384

app = FastAPI(title="Agentic RAG Knowledge Graph", version="1.0.0")

# Global variables
knowledge_graph = nx.DiGraph()
embedding_model = None
vector_store = {}

class DocumentInput(BaseModel):
    id: str
    title: str
    content: str
    metadata: Optional[Dict[str, Any]] = {}

class QueryInput(BaseModel):
    query: str
    max_results: int = 10
    include_context: bool = True
    reasoning_depth: int = 2

class AgentTask(BaseModel):
    task_type: str  # "ingest", "query", "analyze", "synthesize"
    parameters: Dict[str, Any]
    priority: int = 1

class KnowledgeGraphRAG:
    def __init__(self):
        self.graph = nx.DiGraph()
        self.embeddings = {}
        self.documents = {}
        self._init_database()
        
    def _init_database(self):
        """Initialize SQLite database for persistent storage"""
        os.makedirs(os.path.dirname(DATABASE_PATH), exist_ok=True)
        conn = sqlite3.connect(DATABASE_PATH)
        
        conn.execute('''
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                title TEXT,
                content TEXT,
                metadata TEXT,
                embedding BLOB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.execute('''
            CREATE TABLE IF NOT EXISTS entities (
                id TEXT PRIMARY KEY,
                name TEXT,
                type TEXT,
                properties TEXT,
                embedding BLOB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.execute('''
            CREATE TABLE IF NOT EXISTS relations (
                id TEXT PRIMARY KEY,
                source_id TEXT,
                target_id TEXT,
                relation_type TEXT,
                weight REAL,
                properties TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.commit()
        conn.close()
    
    async def ingest_document(self, doc: DocumentInput) -> Dict[str, Any]:
        """Ingest a document and extract entities and relationships"""
        global embedding_model
        
        if embedding_model is None:
            embedding_model = SentenceTransformer(VECTOR_MODEL)
        
        # Generate embedding
        embedding = embedding_model.encode(doc.content)
        
        # Extract entities (simplified - in practice would use NER)
        entities = self._extract_entities(doc.content)
        
        # Extract relationships
        relationships = self._extract_relationships(doc.content, entities)
        
        # Store in graph
        doc_node = f"doc_{doc.id}"
        self.graph.add_node(doc_node, 
                           type="document", 
                           title=doc.title,
                           content=doc.content,
                           metadata=doc.metadata)
        
        # Add entities to graph
        for entity in entities:
            entity_id = f"entity_{uuid.uuid4().hex[:8]}"
            self.graph.add_node(entity_id,
                               type="entity",
                               name=entity["name"],
                               entity_type=entity["type"])
            
            # Connect document to entity
            self.graph.add_edge(doc_node, entity_id, 
                               relation="contains", 
                               weight=entity["confidence"])
        
        # Add relationships
        for rel in relationships:
            self.graph.add_edge(rel["source"], rel["target"],
                               relation=rel["type"],
                               weight=rel["weight"])
        
        # Store in database
        self._store_document(doc, embedding.tobytes())
        
        return {
            "document_id": doc.id,
            "entities_extracted": len(entities),
            "relationships_extracted": len(relationships),
            "graph_nodes": self.graph.number_of_nodes(),
            "graph_edges": self.graph.number_of_edges()
        }
    
    def _extract_entities(self, text: str) -> List[Dict[str, Any]]:
        """Extract entities from text (simplified implementation)"""
        # This is a simplified entity extraction
        # In practice, would use spaCy, transformers, or other NER tools
        import re
        
        entities = []
        
        # Extract capitalized words as potential entities
        words = re.findall(r'\b[A-Z][a-z]+\b', text)
        for word in set(words):
            entities.append({
                "name": word,
                "type": "PERSON" if word in text and len(word) > 2 else "MISC",
                "confidence": 0.7
            })
        
        # Extract numbers as quantities
        numbers = re.findall(r'\b\d+(?:\.\d+)?\b', text)
        for num in set(numbers):
            entities.append({
                "name": num,
                "type": "QUANTITY",
                "confidence": 0.9
            })
        
        return entities[:10]  # Limit to 10 entities
    
    def _extract_relationships(self, text: str, entities: List[Dict]) -> List[Dict[str, Any]]:
        """Extract relationships between entities"""
        relationships = []
        
        # Simple relationship extraction based on proximity
        entity_names = [e["name"] for e in entities]
        
        for i, entity1 in enumerate(entity_names):
            for j, entity2 in enumerate(entity_names[i+1:], i+1):
                if entity1 in text and entity2 in text:
                    # Find if they appear close to each other
                    pos1 = text.find(entity1)
                    pos2 = text.find(entity2)
                    
                    if abs(pos1 - pos2) < 100:  # Within 100 characters
                        relationships.append({
                            "source": f"entity_{entity1}",
                            "target": f"entity_{entity2}",
                            "type": "RELATED_TO",
                            "weight": 0.8
                        })
        
        return relationships
    
    def _store_document(self, doc: DocumentInput, embedding: bytes):
        """Store document in database"""
        conn = sqlite3.connect(DATABASE_PATH)
        conn.execute('''
            INSERT OR REPLACE INTO documents 
            (id, title, content, metadata, embedding)
            VALUES (?, ?, ?, ?, ?)
        ''', (doc.id, doc.title, doc.content, json.dumps(doc.metadata), embedding))
        conn.commit()
        conn.close()
    
    async def query_knowledge_graph(self, query: QueryInput) -> Dict[str, Any]:
        """Query the knowledge graph with agentic reasoning"""
        global embedding_model
        
        if embedding_model is None:
            embedding_model = SentenceTransformer(VECTOR_MODEL)
        
        query_embedding = embedding_model.encode(query.query)
        
        # Find relevant documents using vector similarity
        relevant_docs = self._find_relevant_documents(query_embedding, query.max_results)
        
        # Extract relevant subgraph
        relevant_entities = self._find_relevant_entities(query.query)
        subgraph = self._extract_subgraph(relevant_entities, query.reasoning_depth)
        
        # Generate response using graph reasoning
        response = self._generate_response(query.query, relevant_docs, subgraph)
        
        return {
            "query": query.query,
            "response": response,
            "relevant_documents": len(relevant_docs),
            "graph_nodes_explored": len(subgraph.nodes()),
            "reasoning_paths": self._get_reasoning_paths(subgraph),
            "confidence": 0.85
        }
    
    def _find_relevant_documents(self, query_embedding: np.ndarray, max_results: int) -> List[Dict]:
        """Find documents similar to query using vector search"""
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.execute('SELECT id, title, content, metadata, embedding FROM documents')
        
        similarities = []
        for row in cursor:
            doc_id, title, content, metadata, embedding_blob = row
            doc_embedding = np.frombuffer(embedding_blob, dtype=np.float32)
            
            # Calculate cosine similarity
            similarity = np.dot(query_embedding, doc_embedding) / (
                np.linalg.norm(query_embedding) * np.linalg.norm(doc_embedding)
            )
            
            similarities.append({
                "id": doc_id,
                "title": title,
                "content": content[:500],  # Truncate for response
                "similarity": float(similarity)
            })
        
        conn.close()
        
        # Sort by similarity and return top results
        similarities.sort(key=lambda x: x["similarity"], reverse=True)
        return similarities[:max_results]
    
    def _find_relevant_entities(self, query: str) -> List[str]:
        """Find entities relevant to the query"""
        relevant_entities = []
        
        for node, data in self.graph.nodes(data=True):
            if data.get("type") == "entity":
                entity_name = data.get("name", "")
                if entity_name.lower() in query.lower():
                    relevant_entities.append(node)
        
        return relevant_entities
    
    def _extract_subgraph(self, entities: List[str], depth: int) -> nx.DiGraph:
        """Extract subgraph around relevant entities"""
        if not entities:
            return nx.DiGraph()
        
        # Start with relevant entities
        nodes_to_include = set(entities)
        
        # Expand to neighbors up to specified depth
        for _ in range(depth):
            new_nodes = set()
            for node in nodes_to_include:
                if node in self.graph:
                    new_nodes.update(self.graph.neighbors(node))
                    new_nodes.update(self.graph.predecessors(node))
            nodes_to_include.update(new_nodes)
        
        return self.graph.subgraph(nodes_to_include).copy()
    
    def _generate_response(self, query: str, docs: List[Dict], subgraph: nx.DiGraph) -> str:
        """Generate response using retrieved documents and graph reasoning"""
        # Simplified response generation
        # In practice, would use an LLM for sophisticated reasoning
        
        response_parts = []
        
        if docs:
            response_parts.append("Based on the relevant documents:")
            for i, doc in enumerate(docs[:3], 1):
                response_parts.append(f"{i}. {doc['title']}: {doc['content'][:200]}...")
        
        if subgraph.nodes():
            response_parts.append("\nRelevant knowledge graph connections:")
            for edge in list(subgraph.edges(data=True))[:5]:
                source, target, data = edge
                relation = data.get('relation', 'connected to')
                response_parts.append(f"- {source} {relation} {target}")
        
        if not response_parts:
            return "I don't have enough information to answer your query."
        
        return "\n".join(response_parts)
    
    def _get_reasoning_paths(self, subgraph: nx.DiGraph) -> List[List[str]]:
        """Get reasoning paths through the subgraph"""
        paths = []
        
        # Find simple paths between nodes (limited to avoid explosion)
        nodes = list(subgraph.nodes())[:10]
        
        for i, source in enumerate(nodes):
            for target in nodes[i+1:]:
                try:
                    path = nx.shortest_path(subgraph, source, target)
                    if len(path) <= 4:  # Keep paths short
                        paths.append(path)
                except nx.NetworkXNoPath:
                    continue
        
        return paths[:5]  # Return top 5 paths

# Global instance
rag_system = KnowledgeGraphRAG()

@app.get("/")
async def root():
    return {"message": "Agentic RAG Knowledge Graph", "version": "1.0.0"}

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "graph_nodes": rag_system.graph.number_of_nodes(),
        "graph_edges": rag_system.graph.number_of_edges(),
        "timestamp": datetime.now().isoformat()
    }

@app.post("/ingest")
async def ingest_document(doc: DocumentInput):
    """Ingest a document into the knowledge graph"""
    try:
        result = await rag_system.ingest_document(doc)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/query")
async def query_graph(query: QueryInput):
    """Query the knowledge graph"""
    try:
        result = await rag_system.query_knowledge_graph(query)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/graph/stats")
async def graph_stats():
    """Get knowledge graph statistics"""
    return {
        "nodes": rag_system.graph.number_of_nodes(),
        "edges": rag_system.graph.number_of_edges(),
        "node_types": dict(nx.get_node_attributes(rag_system.graph, 'type')),
        "connected_components": nx.number_connected_components(rag_system.graph.to_undirected())
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=7000)
EOF
        
        # Create requirements.txt
        cat > "$RAG_GRAPH_DATA_DIR/source/requirements.txt" <<EOF
fastapi==0.104.1
uvicorn==0.24.0
networkx==3.2.1
numpy==1.24.3
sentence-transformers==2.2.2
pydantic==2.4.2
sqlite3
EOF
        
        # Create Dockerfile
        cat > "$RAG_GRAPH_DATA_DIR/source/Dockerfile" <<'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 7000

CMD ["python", "app.py"]
EOF
    fi
    
    # Create docker-compose configuration
    cat > "$PROJECT_ROOT/docker-compose.agentic-rag-knowledge-graph.yml" <<EOF
version: '3.8'
services:
  agentic-rag-graph:
    build:
      context: ${RAG_GRAPH_DATA_DIR}/source
      dockerfile: Dockerfile
    ports:
      - "${RAG_GRAPH_PORT}:7000"
    volumes:
      - ${RAG_GRAPH_DATA_DIR}/data:/app/data
      - ${RAG_GRAPH_DATA_DIR}/models:/app/models
    environment:
      - PYTHONUNBUFFERED=1
      - DATABASE_URL=sqlite:///app/data/knowledge_graph.db
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7000/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

volumes:
  rag_graph_data:
EOF
    
    echo "Building and starting Agentic RAG Knowledge Graph..."
    docker compose -f "$PROJECT_ROOT/docker-compose.agentic-rag-knowledge-graph.yml" up -d --build
    
    echo "Waiting for service to be ready..."
    sleep 30
    
    # Wait for service to be ready
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -f "http://localhost:$RAG_GRAPH_PORT/health" &>/dev/null; then
            echo "Agentic RAG Knowledge Graph is ready!"
            break
        fi
        echo "Waiting for service... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "Error: Agentic RAG Knowledge Graph failed to start within expected time"
        exit 1
    fi
    
elif [[ "$INSTALL_TYPE" == "bare-metal" ]]; then
    echo "Bare metal installation requires Python 3.11+ and manual setup."
    echo "Please use Docker installation for easier deployment."
    exit 1
fi

# Test installation
echo "Testing Agentic RAG Knowledge Graph installation..."
sleep 5

if curl -f "http://localhost:$RAG_GRAPH_PORT/health" &>/dev/null; then
    echo "✅ Agentic RAG Knowledge Graph is running successfully!"
    echo "📊 API Endpoint: http://localhost:$RAG_GRAPH_PORT"
    echo ""
    echo "📚 Available endpoints:"
    echo "  - POST /ingest - Ingest documents"
    echo "  - POST /query - Query knowledge graph"
    echo "  - GET /graph/stats - Graph statistics"
    echo ""
    echo "Example usage:"
    echo "# Ingest a document"
    echo "curl -X POST http://localhost:$RAG_GRAPH_PORT/ingest \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"id\": \"doc1\", \"title\": \"Test Document\", \"content\": \"This is a test document about AI and machine learning.\"}'"
    echo ""
    echo "# Query the knowledge graph"
    echo "curl -X POST http://localhost:$RAG_GRAPH_PORT/query \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"query\": \"What is AI?\", \"max_results\": 5}'"
else
    echo "❌ Error: Agentic RAG Knowledge Graph is not responding"
    exit 1
fi

echo "Agentic RAG Knowledge Graph installation completed successfully!"