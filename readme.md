## AgentCompass FastAPI Service for CognitiveKernel-Pro

A lightweight HTTP service around CognitiveKernel-Pro, implemented in FastAPI and served via Uvicorn. It exposes a simple REST API to run CKAgent synchronously and return the final answer plus the full trajectory.

Repository reference: CognitiveKernel-Pro (upstream): https://github.com/Tencent/CognitiveKernel-Pro


### What this provides
- FastAPI app defined in agentcompass_service_fastapi.py
- Endpoints:
  - GET /health — health check
  - POST /api/tasks — run a single task and return results
- Concurrent handling via multiple Uvicorn workers (no threading needed)


## 1) Environment setup

- Python: 3.12 recommended
- Install Python dependencies (FastAPI/Uvicorn + CK-Pro deps)
````bash
pip install fastapi uvicorn
pip install boto3 botocore openai ddgs rich numpy openpyxl biopython mammoth markdownify pandas pdfminer-six python-pptx pdf2image puremagic pydub SpeechRecognition bs4 youtube-transcript-api requests transformers protobuf openai langchain_openai langchain
pip install selenium helium smolagents
````

- Optional (for web browsing capability used by web_agent): run the Playwright-based web server under ck_pro/ck_web/_web.
  - Linux: ck_pro/ck_web/_web/run_local.sh
  - macOS: ck_pro/ck_web/_web/run_local_mac.sh
  - After setup, typical start:
````bash
LISTEN_PORT=3001 npm start
````

## 2) Configuration (.env)

````bash
cp .env.template .env
````
Key variables you may want to set:
- SEARCH_BACKEND: DuckDuckGo (default), Google (CSE), or SerpAPI
- WEB_IP: host:port for the web browser service (default: localhost:3001)
- Provider keys if using Azure OpenAI or others (see upstream README for details)

### Agent Configuration

All agents in this project are configured with the following default settings:
- **max_steps**: 10 - Maximum number of steps each agent can take to solve a task
  - This applies to all agents: CKAgent (main agent), WebAgent, and FileAgent
  - The actual execution may allow slightly more steps (up to 1.5x) to compensate for error recovery
  - You can override this at runtime by passing `max_steps` parameter to the agent's `run()` method


## 3) Run the API server
- Recommended (multiple workers):
````bash
uvicorn agentcompass_service_fastapi:app --host 0.0.0.0 --port 8080 --workers 4
````
- Or run the script directly (single- or multi-worker):
````bash
python agentcompass_service_fastapi.py --host 0.0.0.0 --port 8080 --workers 1
````

Health check:
````bash
curl -s http://localhost:8080/health
````

## 4) Docker Deployment (Recommended)

The easiest way to run this service is using Docker. The Docker image includes both the FastAPI service and the Playwright web browser service.

### Quick Start with Docker

````bash
# Pull and run the image (use specific version or latest)
docker run -d \
  --name agentcompass-service \
  -p 8080:8080 \
  -p 3001:3001 \
  --shm-size=2g \
  -e SEARCH_BACKEND=DuckDuckGo \
  -e WORKERS=4 \
  opencompass/cognitivekernel-pro-service:v1.0.0

# Check health
curl http://localhost:8080/health
````

### Using Docker Compose

````bash
# Download docker-compose.yml
wget https://raw.githubusercontent.com/Tencent/CognitiveKernel-Pro/main/docker/docker-compose.yml

# Start service
docker-compose up -d

# View logs
docker-compose logs -f
````

### Build Your Own Image

````bash
# Build locally with version tag
docker build -t opencompass/cognitivekernel-pro-service:v1.0.0 .

# Or use the automated script (default version: v1.0.0)
cd docker
./build-and-push.sh v1.0.0
````

For detailed Docker deployment instructions, see [docker/README.md](docker/README.md).

## 5) Upstream project
This service wraps the CKAgent from CognitiveKernel-Pro. For full agent capabilities, training recipes, datasets, and more instructions, see the original repository:
- CognitiveKernel-Pro: https://github.com/Tencent/CognitiveKernel-Pro

If you use this service in your work, please also cite or reference CognitiveKernel-Pro accordingly.
