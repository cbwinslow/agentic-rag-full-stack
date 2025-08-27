#!/usr/bin/env bash
set -euo pipefail

# demo_installation.sh
# Demonstration of the complete installation system

echo "🚀 Agentic RAG Full Stack Installation Demo"
echo "============================================"
echo ""

echo "📋 Available Services:"
echo "----------------------"
./scripts/install/install_all.sh --help | grep -A 20 "Available services:" | head -20

echo ""
echo "📂 Available Categories:"
echo "------------------------"
./scripts/install/install_all.sh --help | grep -A 10 "Available categories:" | head -10

echo ""
echo "🔍 Dry Run Examples:"
echo "--------------------"

echo "1. Core services dry run:"
./scripts/install/install_all.sh --dry-run --category core

echo ""
echo "2. AI services dry run:"
./scripts/install/install_all.sh --dry-run --category ai

echo ""
echo "3. Monitoring services dry run:"
./scripts/install/install_all.sh --dry-run --category monitoring

echo ""
echo "4. Vector databases dry run:"
./scripts/install/install_all.sh --dry-run --category vector

echo ""
echo "5. All services dry run:"
./scripts/install/install_all.sh --dry-run --category all

echo ""
echo "✅ Demo completed successfully!"
echo ""
echo "📚 To start actual installation:"
echo "   ./scripts/install/install_all.sh --category core"
echo "   ./scripts/install/install_all.sh --category ai"
echo "   ./scripts/install/install_all.sh --services weaviate,grafana"
echo ""
echo "📊 Individual script examples:"
echo "   ./scripts/install/weaviate.sh --docker --port 8080"
echo "   ./scripts/install/grafana.sh --docker --port 3000"
echo "   ./scripts/install/clickhouse.sh --bare-metal"