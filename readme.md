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

## 4) Upstream project
This service wraps the CKAgent from CognitiveKernel-Pro. For full agent capabilities, training recipes, datasets, and more instructions, see the original repository:
- CognitiveKernel-Pro: https://github.com/Tencent/CognitiveKernel-Pro

If you use this service in your work, please also cite or reference CognitiveKernel-Pro accordingly.

