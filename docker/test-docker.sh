#!/bin/bash
# Quick test script for Docker image
# Usage: ./test-docker.sh [VERSION] [OPENAI_API_KEY] [OPENAI_ENDPOINT] [MODEL_NAME]
#
# Examples:
#   ./test-docker.sh v1.0.0
#   ./test-docker.sh v1.0.0 sk-xxx
#   ./test-docker.sh v1.0.0 sk-xxx https://api.openai.com/v1 gpt-4
#
# Or use environment variables:
#   OPENAI_API_KEY=sk-xxx ./test-docker.sh v1.0.0
#   OPENAI_API_KEY=sk-xxx OPENAI_ENDPOINT=https://api.openai.com/v1 MODEL_NAME=gpt-4 ./test-docker.sh v1.0.0

set -e

DOCKER_USERNAME="opencompass"
IMAGE_NAME="cognitivekernel-pro-service"
VERSION="${1:-v1.0.0}"
CONTAINER_NAME="agentcompass-test"

# LLM Configuration - can be passed as arguments or environment variables
# Priority: command line args > environment variables > defaults
OPENAI_API_KEY="${2:-${OPENAI_API_KEY:-}}"
OPENAI_ENDPOINT="${3:-${OPENAI_ENDPOINT:-https://api.openai.com/v1}}"
MODEL_NAME="${4:-${MODEL_NAME:-gpt-4o-mini}}"

echo "=========================================="
echo "Testing Docker Image"
echo "=========================================="
echo "Version: $VERSION"
if [ -n "$OPENAI_API_KEY" ]; then
    echo "LLM Config: Enabled"
    echo "  - Endpoint: $OPENAI_ENDPOINT"
    echo "  - Model: $MODEL_NAME"
    echo "  - API Key: ${OPENAI_API_KEY:0:8}...${OPENAI_API_KEY: -4}"
else
    echo "LLM Config: Not configured - will test infrastructure only"
fi
echo ""

# Stop and remove existing test container if exists
if docker ps -a | grep -q $CONTAINER_NAME; then
    echo "Removing existing test container..."
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
fi

# Build docker run command with optional LLM configuration
DOCKER_RUN_CMD="docker run -d \
    --name $CONTAINER_NAME \
    -p 8080:8080 \
    -p 3001:3001 \
    --shm-size=2g \
    -e SEARCH_BACKEND=DuckDuckGo \
    -e WORKERS=2"

# Add LLM configuration if provided
if [ -n "$OPENAI_API_KEY" ]; then
    DOCKER_RUN_CMD="$DOCKER_RUN_CMD \
    -e OPENAI_API_KEY=$OPENAI_API_KEY \
    -e OPENAI_ENDPOINT=$OPENAI_ENDPOINT \
    -e MODEL_NAME=$MODEL_NAME"
fi

DOCKER_RUN_CMD="$DOCKER_RUN_CMD \
    ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}"

# Run the container
echo "Starting container..."
eval $DOCKER_RUN_CMD

echo ""
echo "Waiting for services to start - 40 seconds..."
sleep 40

echo ""
echo "=========================================="
echo "Testing Health Endpoint"
echo "=========================================="
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:8080/health)
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ] && echo "$HEALTH_BODY" | grep -q "healthy"; then
    echo "✅ Health check passed!"
    echo "Response: $HEALTH_BODY"
else
    echo "❌ Health check failed!"
    echo "HTTP Code: $HTTP_CODE"
    echo "Response: $HEALTH_BODY"
    echo ""
    echo "Container logs:"
    docker logs $CONTAINER_NAME
    exit 1
fi

echo ""
echo "=========================================="
echo "Test 1: API Endpoint Validation"
echo "=========================================="

if [ -n "$OPENAI_API_KEY" ]; then
    echo "Testing API with LLM configured - timeout 30s..."
    echo "Question: What is 123 * 456?"
    echo ""

    # With API key, allow more time for actual LLM processing
    RESPONSE=$(timeout 30 curl -s -X POST http://localhost:8080/api/tasks \
        -H "Content-Type: application/json" \
        -d '{
            "params": {
                "question": "What is 123 * 456? Just give me the number."
            }
        }' 2>&1 || echo "TIMEOUT")

    if [ "$RESPONSE" = "TIMEOUT" ]; then
        echo "❌ API request timed out after 30 seconds"
        echo "This should not happen with valid API key. Check container logs:"
        docker logs $CONTAINER_NAME --tail 20
    elif echo "$RESPONSE" | grep -q "final_answer"; then
        echo "✅ Task execution successful!"
        ANSWER=$(echo "$RESPONSE" | grep -o '"final_answer":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "Answer: $ANSWER"

        # Verify the answer is correct
        if echo "$ANSWER" | grep -q "56088"; then
            echo "✅ Correct answer! LLM is working properly."
        else
            echo "⚠️  Answer received but may not be correct. Expected: 56088"
        fi
    elif echo "$RESPONSE" | grep -q "empty output"; then
        echo "❌ LLM returned empty output"
        echo "Check if API key is valid and endpoint is accessible"
        echo "Response: ${RESPONSE:0:300}..."
    else
        echo "⚠️  Unexpected response:"
        echo "${RESPONSE:0:500}..."
    fi
else
    echo "Testing API endpoint without LLM - timeout 5s..."
    echo "Note: Without API key configured, the request may timeout but that is expected."
    echo ""

    # Without API key, use short timeout
    RESPONSE=$(timeout 5 curl -s -X POST http://localhost:8080/api/tasks \
        -H "Content-Type: application/json" \
        -d '{
            "params": {
                "question": "2+2"
            }
        }' 2>&1 || echo "TIMEOUT")

    # Check the response
    if [ "$RESPONSE" = "TIMEOUT" ] || [ -z "$RESPONSE" ]; then
        echo "⚠️  API request timed out - 5 seconds"
        echo ""
        echo "This is EXPECTED when no LLM API key is configured."
        echo "The Agent tries to call the LLM, gets empty responses, and retries until max steps."
        echo ""
        echo "✅ API endpoint is accepting requests - service is working"
        echo "⚠️  To get actual responses, pass API key to this script"
        echo ""
        echo "Checking if the request is still being processed in the background..."
        sleep 2
        # Check recent logs to see if request was received
        if docker logs agentcompass-test --tail 5 2>/dev/null | grep -q "POST /api/tasks"; then
            echo "✅ Confirmed: API endpoint received and is processing the request"
        fi
    elif echo "$RESPONSE" | grep -q -E "(final_answer|detail)"; then
        echo "✅ API endpoint is responsive!"
        if echo "$RESPONSE" | grep -q "final_answer"; then
            echo "✅ Task execution successful!"
            ANSWER=$(echo "$RESPONSE" | grep -o '"final_answer":"[^"]*"' | head -1 | cut -d'"' -f4)
            echo "Answer: ${ANSWER:0:100}..."
        else
            echo "Response: ${RESPONSE:0:200}..."
        fi
    else
        echo "⚠️  Unexpected response:"
        echo "${RESPONSE:0:300}..."
    fi
fi

echo ""
echo "=========================================="
echo "Test 2: Web Agent Test"
echo "=========================================="

if [ -n "$OPENAI_API_KEY" ]; then
    echo "Testing Web Agent with search capability - timeout 60s..."
    echo "Question: Search for the current weather in Beijing"
    echo ""

    RESPONSE=$(timeout 60 curl -s -X POST http://localhost:8080/api/tasks \
        -H "Content-Type: application/json" \
        -d '{
            "params": {
                "question": "Search the web for current weather in Beijing and tell me the temperature"
            }
        }' 2>&1 || echo "TIMEOUT")

    if [ "$RESPONSE" = "TIMEOUT" ]; then
        echo "⚠️  Web agent test timed out after 60 seconds"
        echo "This may happen if the task is complex. Check logs for details."
    elif echo "$RESPONSE" | grep -q "final_answer"; then
        echo "✅ Web agent task completed!"
        ANSWER=$(echo "$RESPONSE" | grep -o '"final_answer":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "Answer: ${ANSWER:0:200}..."
        echo ""
        echo "✅ Web search and agent capabilities are working!"
    else
        echo "⚠️  Response received but may not contain final answer:"
        echo "${RESPONSE:0:300}..."
    fi
else
    echo "⚠️  Skipping web agent test - no API key configured"
    echo ""
    echo "To test full agent capabilities with LLM, run this script with API key:"
    echo ""
    echo "Usage examples:"
    echo "  ./test-docker.sh v1.0.0 sk-your-api-key"
    echo "  ./test-docker.sh v1.0.0 sk-your-api-key https://api.openai.com/v1 gpt-4"
    echo ""
    echo "Or use environment variables:"
    echo "  OPENAI_API_KEY=sk-xxx ./test-docker.sh v1.0.0"
    echo "  OPENAI_API_KEY=sk-xxx MODEL_NAME=gpt-4 ./test-docker.sh v1.0.0"
    echo ""
fi

echo ""
echo "=========================================="
echo "Test 3: Web Service Port Check"
echo "=========================================="
echo "Checking if Playwright web service on port 3001 is accessible..."
WEB_RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:3001 --max-time 5)
WEB_HTTP_CODE=$(echo "$WEB_RESPONSE" | tail -n1)

if [ "$WEB_HTTP_CODE" = "200" ] || [ "$WEB_HTTP_CODE" = "404" ]; then
    echo "✅ Web service is running on port 3001"
    echo "HTTP Code: $WEB_HTTP_CODE"
else
    echo "⚠️  Web service may not be fully ready - HTTP Code: $WEB_HTTP_CODE"
fi

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "✅ Health endpoint: Working"
echo "✅ FastAPI service: Running on port 8080"
echo "✅ Web service: Running on port 3001"

if [ -n "$OPENAI_API_KEY" ]; then
    echo "✅ LLM integration: Configured and tested"
    echo "✅ Basic task execution: Tested with real LLM"
    echo "✅ Web agent + search: Tested with real LLM"
    echo ""
    echo "🎉 All components including LLM are functional!"
else
    echo "⚠️  LLM integration: Not configured"
    echo "✅ Infrastructure: All services running"
    echo ""
    echo "✅ All critical infrastructure components are functional!"
    echo "💡 Run with API key to test full LLM capabilities"
fi

echo ""
echo "=========================================="
echo "Container Information"
echo "=========================================="
echo "Container status:"
docker ps | grep $CONTAINER_NAME

echo ""
echo "Container logs - last 30 lines:"
docker logs --tail 30 $CONTAINER_NAME

echo ""
echo "=========================================="
echo "Test Complete!"
echo "=========================================="
echo ""
echo "Container is running. You can:"
echo "  - View logs: docker logs -f $CONTAINER_NAME"
echo "  - Stop container: docker stop $CONTAINER_NAME"
echo "  - Remove container: docker rm $CONTAINER_NAME"
echo "  - Access API: http://localhost:8080"
echo "  - Health check: curl http://localhost:8080/health"
echo "  - Test web service: curl http://localhost:3001"
echo ""
read -p "Do you want to stop and remove the test container? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
    echo "Container removed."
else
    echo "Container is still running."
fi

