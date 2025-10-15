#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Start the Playwright web service in background
echo "Starting Playwright web service on port 3001..."
cd "$SCRIPT_DIR/ck_pro/ck_web/_web"
LISTEN_PORT=3001 npm start &
WEB_PID=$!

# Wait for web service to be ready
echo "Waiting for web service to start..."
sleep 5

# Start the FastAPI service
echo "Starting FastAPI service on port 8080..."
cd "$SCRIPT_DIR"
exec uvicorn agentcompass_service_fastapi:app --host 0.0.0.0 --port 8080 --workers ${WORKERS:-4}