# Docker 部署指南 / Docker Deployment Guide

CognitiveKernel-Pro AgentCompass 服务的 Docker 化部署完整指南。

---

## 📋 目录 / Table of Contents

- [快速开始](#-快速开始--quick-start)（用户）
- [构建和推送](#-构建和推送--build--push)（开发者）
- [配置说明](#-配置说明--configuration)
- [故障排查](#-故障排查--troubleshooting)

---

## 🚀 快速开始 / Quick Start

### 用户：直接使用镜像 / For Users: Use Pre-built Image

```bash
# 1. 拉取镜像（推荐使用版本号）
docker pull opencompass/cognitivekernel-pro-service:v1.0.0

# 2. 运行容器
docker run -d \
  --name agentcompass-service \
  -p 8080:8080 \
  -p 3001:3001 \
  --shm-size=2g \
  opencompass/cognitivekernel-pro-service:v1.0.0

# 3. 测试服务
curl http://localhost:8080/health

# 4. 查看日志
docker logs -f agentcompass-service

# 5. 停止服务
docker stop agentcompass-service
docker rm agentcompass-service
```

### 使用 Docker Compose（推荐）/ Using Docker Compose (Recommended)

```bash
# 1. 启动服务
docker-compose up -d

# 2. 查看日志
docker-compose logs -f

# 3. 停止服务
docker-compose down
```

---

## 🔨 构建和推送 / Build & Push

### 开发者：构建镜像 / For Developers: Build Image

#### 方式 1: 使用自动化脚本（推荐）

```bash
# 构建、测试、推送一条龙
cd docker
./build-and-push.sh v1.0.0

# 脚本会自动：
# 1. 构建镜像并打上 v1.0.0 和 latest 标签
# 2. 运行测试验证镜像
# 3. 推送到 Docker Hub（需要先登录）
```

#### 方式 2: 手动构建

```bash
# 1. 构建镜像
docker build -t opencompass/cognitivekernel-pro-service:v1.0.0 .

# 2. 同时打上 latest 标签
docker tag opencompass/cognitivekernel-pro-service:v1.0.0 \
           opencompass/cognitivekernel-pro-service:latest

# 3. 测试镜像
cd docker
./test-docker.sh v1.0.0

# 4. 登录 Docker Hub
docker login
# Username: opencompass
# Password: [your password]

# 5. 推送镜像
docker push opencompass/cognitivekernel-pro-service:v1.0.0
docker push opencompass/cognitivekernel-pro-service:latest
```

### 版本管理建议 / Version Management

- **生产环境**: 使用具体版本号 \`v1.0.0\`, \`v1.1.0\` 等
- **测试环境**: 可以使用 \`latest\` 快速获取最新版本
- **发布新版本**: 修改版本号，如 \`v1.1.0\`，同时更新 \`latest\`

---

## ⚙️ 配置说明 / Configuration

### 环境变量 / Environment Variables

```bash
docker run -d \
  --name agentcompass-service \
  -p 8080:8080 \
  -p 3001:3001 \
  --shm-size=2g \
  -e SEARCH_BACKEND=DuckDuckGo \
  -e DDG_REGION=us-en \
  -e WORKERS=4 \
  -e OPENAI_API_KEY=sk-xxx \
  -e OPENAI_ENDPOINT=https://api.openai.com/v1 \
  opencompass/cognitivekernel-pro-service:v1.0.0
```

**可用环境变量**:

| 变量 | 说明 | 默认值 |
|------|------|--------|
| \`SEARCH_BACKEND\` | 搜索引擎 (DuckDuckGo/Google/SerpAPI) | \`DuckDuckGo\` |
| \`DDG_REGION\` | DuckDuckGo 地区设置 | \`wt-wt\` |
| \`WORKERS\` | Uvicorn 工作进程数 | \`4\` |
| \`WEB_IP\` | Web 浏览器服务地址 | \`localhost:3001\` |
| \`OPENAI_API_KEY\` | OpenAI API 密钥 | - |
| \`OPENAI_ENDPOINT\` | OpenAI API 端点 | \`https://api.openai.com/v1\` |
| \`GOOGLE_API_KEY\` | Google CSE API 密钥 | - |
| \`GOOGLE_CSE_ID\` | Google CSE ID | - |
| \`SERPAPI_API_KEY\` | SerpAPI 密钥 | - |

### 数据持久化 / Data Persistence

```bash
docker run -d \
  --name agentcompass-service \
  -p 8080:8080 \
  -p 3001:3001 \
  --shm-size=2g \
  -v $(pwd)/test_output:/app/test_output \
  -v $(pwd)/.env:/app/.env:ro \
  opencompass/cognitivekernel-pro-service:v1.0.0
```

### 重要参数说明 / Important Parameters

- **\`--shm-size=2g\`**: 必需！Playwright/Chromium 需要共享内存
- **\`-p 8080:8080\`**: FastAPI 服务端口
- **\`-p 3001:3001\`**: Playwright Web 服务端口

---

## 🐛 故障排查 / Troubleshooting

### 查看日志 / View Logs

```bash
# 查看容器日志
docker logs -f agentcompass-service

# 查看最近 100 行
docker logs --tail 100 agentcompass-service
```

### 进入容器调试 / Debug Inside Container

```bash
# 进入容器
docker exec -it agentcompass-service bash

# 检查服务状态
curl http://localhost:8080/health
curl http://localhost:3001

# 查看进程
ps aux | grep -E "uvicorn|node"
```

### 常见问题 / Common Issues

#### 1. 端口被占用 / Port Already in Use

```bash
# 检查端口占用
lsof -i :8080
lsof -i :3001

# 使用不同端口
docker run -d -p 8888:8080 -p 3002:3001 ...
```

#### 2. Chromium 崩溃 / Chromium Crashes

```bash
# 确保使用了 --shm-size=2g
docker run -d --shm-size=2g ...

# 或使用 --ipc=host
docker run -d --ipc=host ...
```

#### 3. 构建失败 / Build Fails

```bash
# 清理 Docker 缓存
docker system prune -a

# 无缓存重新构建
docker build --no-cache -t opencompass/cognitivekernel-pro-service:v1.0.0 .
```

#### 4. 服务无响应 / Service Not Responding

```bash
# 检查容器状态
docker ps -a

# 重启容器
docker restart agentcompass-service

# 查看资源使用
docker stats agentcompass-service
```

---

## 📁 文件说明 / File Description

```
docker/
├── Dockerfile              # 在项目根目录（必须）
├── .dockerignore          # 在项目根目录（必须）
├── docker-compose.yml     # Docker Compose 配置
├── build-and-push.sh      # 自动化构建推送脚本
├── test-docker.sh         # 镜像测试脚本
├── README.md              # 本文档
└── DOCKER_HUB_README.md   # Docker Hub 仓库说明
```

---

## 🔗 相关链接 / Links

- **GitHub**: https://github.com/Tencent/CognitiveKernel-Pro
- **Docker Hub**: https://hub.docker.com/r/opencompass/cognitivekernel-pro-service
- **维护者**: OpenCompass Team

---

## 📝 快速参考 / Quick Reference

### 常用命令 / Common Commands

```bash
# 拉取镜像
docker pull opencompass/cognitivekernel-pro-service:v1.0.0

# 运行容器
docker run -d --name agentcompass-service -p 8080:8080 -p 3001:3001 --shm-size=2g opencompass/cognitivekernel-pro-service:v1.0.0

# 查看日志
docker logs -f agentcompass-service

# 停止容器
docker stop agentcompass-service

# 删除容器
docker rm agentcompass-service

# 删除镜像
docker rmi opencompass/cognitivekernel-pro-service:v1.0.0

# 构建镜像
docker build -t opencompass/cognitivekernel-pro-service:v1.0.0 .

# 推送镜像
docker push opencompass/cognitivekernel-pro-service:v1.0.0
```

---

**最后更新**: 2025-10-13  
**维护者**: OpenCompass Team
