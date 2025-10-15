# Multi-stage Dockerfile for CognitiveKernel-Pro AgentCompass Service
# This image includes both the FastAPI service and the Playwright web browser service

FROM node:20-slim AS web-builder

# Install Playwright dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app/ck_pro/ck_web/_web

# Copy web service files
COPY ck_pro/ck_web/_web/package*.json ./
COPY ck_pro/ck_web/_web/server.js ./

# Install Node.js dependencies
RUN npm install && \
    npm install uuid js-yaml playwright-extra puppeteer-extra-plugin-stealth async-mutex

# Install Playwright browsers
RUN npx playwright install chromium
RUN npx playwright install-deps chromium

# Create necessary directories
RUN mkdir -p ./DownloadedFiles ./screenshots


# ============================================
# Main Python service stage
# ============================================
FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    ca-certificates \
    curl \
    git \
    # For Playwright
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libatspi2.0-0 \
    # For audio processing
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (needed for web service)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Upgrade pip and install build tools
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Copy Python dependencies installation info from README
# Install Python dependencies in stages to avoid timeout and memory issues

# Stage 1: Install PyTorch CPU version first (largest package)
# Using official PyTorch CPU index for smaller size
RUN pip install --no-cache-dir --default-timeout=100 torch --index-url https://download.pytorch.org/whl/cpu

# Stage 2: Install core dependencies
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    boto3 \
    botocore \
    openai \
    requests

# Stage 3: Install data processing libraries
RUN pip install --no-cache-dir \
    numpy \
    pandas \
    openpyxl \
    pdfminer-six \
    python-pptx \
    pdf2image \
    puremagic

# Stage 4: Install document and media processing
RUN pip install --no-cache-dir \
    biopython \
    mammoth \
    markdownify \
    pydub \
    SpeechRecognition

# Stage 5: Install web scraping and search
RUN pip install --no-cache-dir \
    ddgs \
    bs4 \
    youtube-transcript-api \
    selenium \
    helium

# Stage 6: Install AI/ML libraries
RUN pip install --no-cache-dir \
    transformers \
    protobuf \
    langchain_openai \
    langchain \
    smolagents

# Stage 7: Install utilities
RUN pip install --no-cache-dir rich

# Pre-download and cache the Qwen tokenizer to avoid download on first run
RUN python3 -c "from transformers import AutoTokenizer; AutoTokenizer.from_pretrained('Qwen/Qwen3-32B')"

# Copy the entire project
COPY . /app/

# Copy web service from builder stage
COPY --from=web-builder /app/ck_pro/ck_web/_web /app/ck_pro/ck_web/_web
COPY --from=web-builder /root/.cache/ms-playwright /root/.cache/ms-playwright

# Create .env from template if not exists
RUN if [ ! -f .env ]; then cp .env.template .env; fi

# Create necessary directories
RUN mkdir -p test_output ck_pro/ck_web/_web/DownloadedFiles ck_pro/ck_web/_web/screenshots

# Expose ports
# 8080 for FastAPI service
# 3001 for Playwright web service
EXPOSE 8080 3001

# Copy startup script
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Set environment variables
ENV PYTHONPATH=/app
ENV WEB_IP=localhost:3001
ENV SEARCH_BACKEND=DuckDuckGo
ENV DDG_REGION=us-en
ENV DDG_SAFESEARCH=moderate

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the startup script
CMD ["/app/start.sh"]
