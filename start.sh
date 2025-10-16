#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Start the Playwright web service in background
echo "========================================"
echo "🚀 Starting CognitiveKernel-Pro Services"
echo "========================================"
cd "$SCRIPT_DIR/ck_pro/ck_web/_web"

# Display proxy configuration if set
if [ -n "$HTTP_PROXY" ] || [ -n "$http_proxy" ] || [ -n "$HTTPS_PROXY" ] || [ -n "$https_proxy" ]; then
    echo ""
    echo "🌐 PROXY CONFIGURATION DETECTED:"
    echo "----------------------------------------"
    [ -n "$HTTP_PROXY" ] && echo "  ✓ HTTP_PROXY=$HTTP_PROXY"
    [ -n "$http_proxy" ] && echo "  ✓ http_proxy=$http_proxy"
    [ -n "$HTTPS_PROXY" ] && echo "  ✓ HTTPS_PROXY=$HTTPS_PROXY"
    [ -n "$https_proxy" ] && echo "  ✓ https_proxy=$https_proxy"
    [ -n "$NO_PROXY" ] && echo "  ✓ NO_PROXY=$NO_PROXY"
    [ -n "$no_proxy" ] && echo "  ✓ no_proxy=$no_proxy"
    echo "----------------------------------------"
    echo "✓ Browser will use proxy for network access"
    echo ""
else
    echo ""
    echo "⚠️  NO PROXY CONFIGURED"
    echo "----------------------------------------"
    echo "  Browser will use direct connection"
    echo "  If network access fails, set:"
    echo "    -e HTTPS_PROXY=http://your-proxy:port"
    echo "----------------------------------------"
    echo ""
fi

echo "📡 Starting Playwright web service on port 3001..."

# Start npm with proxy environment variables explicitly passed
env LISTEN_PORT=3001 \
    HTTP_PROXY="${HTTP_PROXY:-${http_proxy}}" \
    HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy}}" \
    NO_PROXY="${NO_PROXY:-${no_proxy}}" \
    npm start &
WEB_PID=$!

# Wait for web service to be ready
echo "Waiting for web service to start..."
sleep 5

# Start the FastAPI service
echo "Starting FastAPI service on port 8080..."
cd "$SCRIPT_DIR"
exec uvicorn agentcompass_service_fastapi:app --host 0.0.0.0 --port 8080 --workers ${WORKERS:-4}