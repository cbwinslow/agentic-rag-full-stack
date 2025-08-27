#!/usr/bin/env bash
set -euo pipefail

# Bootstrap pyenv and install the project's python version, create venv, and
# install dependencies with `uv` (a lightweight dependency manager wrapper).

PYTHON_VERSION_FILE=".python-version"
PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"

if ! command -v pyenv >/dev/null 2>&1; then
  echo "pyenv not found. Please install pyenv first: https://github.com/pyenv/pyenv#installation"
  exit 1
fi

cd "$(dirname "$0")/.."

PY_VERSION=$(cat "$PYTHON_VERSION_FILE")
echo "Using Python version: $PY_VERSION"

echo "Installing Python $PY_VERSION via pyenv (if needed)"
pyenv install -s "$PY_VERSION"

echo "Creating virtualenv"
pyenv virtualenv -f "$PY_VERSION" agentic-rag-venv || true
pyenv local agentic-rag-venv

echo "Upgrading pip and installing uv"
python -m pip install --upgrade pip
python -m pip install uv-cli

if [ -f requirements.txt ]; then
  echo "Installing Python requirements.txt"
  uv install -r requirements.txt || pip install -r requirements.txt
fi

echo "Python environment ready. Use 'pyenv activate agentic-rag-venv' to enter it, or 'pyenv local agentic-rag-venv' in this directory." 
