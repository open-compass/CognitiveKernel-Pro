#!/bin/bash
# Build and push Docker image to Docker Hub
# Usage: ./build-and-push.sh [version]

set -e

# Configuration
DOCKER_USERNAME="opencompass"
IMAGE_NAME="cognitivekernel-pro-service"
VERSION="${1:-v1.0.0}"

echo "=========================================="
echo "Building Docker Image"
echo "=========================================="
echo "Username: $DOCKER_USERNAME"
echo "Image: $IMAGE_NAME"
echo "Version: $VERSION"
echo "=========================================="

# Build the image
echo ""
echo "Step 1: Building Docker image..."
docker build -t ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION} -f ../Dockerfile ..

# Always tag as latest for convenience
echo ""
echo "Step 2: Tagging as latest..."
docker tag ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION} ${DOCKER_USERNAME}/${IMAGE_NAME}:latest

# Test the image
echo ""
echo "Step 3: Testing the image..."
echo "Starting test container..."
docker run -d \
    --name agentcompass-test-$$ \
    -p 18080:8080 \
    -p 13001:3001 \
    --shm-size=2g \
    ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}

echo "Waiting for service to start (30 seconds)..."
sleep 30

echo "Testing health endpoint..."
if curl -f http://localhost:18080/health; then
    echo ""
    echo "✅ Health check passed!"
else
    echo ""
    echo "❌ Health check failed!"
    docker logs agentcompass-test-$$
    docker stop agentcompass-test-$$
    docker rm agentcompass-test-$$
    exit 1
fi

echo ""
echo "Cleaning up test container..."
docker stop agentcompass-test-$$
docker rm agentcompass-test-$$

# Push to Docker Hub
echo ""
echo "Step 4: Pushing to Docker Hub..."
read -p "Do you want to push to Docker Hub? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Logging in to Docker Hub..."
    docker login
    
    echo "Pushing ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}..."
    docker push ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}

    echo "Pushing ${DOCKER_USERNAME}/${IMAGE_NAME}:latest..."
    docker push ${DOCKER_USERNAME}/${IMAGE_NAME}:latest
    
    echo ""
    echo "=========================================="
    echo "✅ Successfully pushed to Docker Hub!"
    echo "=========================================="
    echo "Image: ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}"
    echo "Also tagged as: ${DOCKER_USERNAME}/${IMAGE_NAME}:latest"
    echo ""
    echo "Users can pull with:"
    echo "  docker pull ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}"
    echo "  docker pull ${DOCKER_USERNAME}/${IMAGE_NAME}:latest"
    echo ""
    echo "Or run directly with:"
    echo "  docker run -d -p 8080:8080 -p 3001:3001 --shm-size=2g ${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION}"
    echo "=========================================="
else
    echo "Skipping push to Docker Hub."
fi

echo ""
echo "Done!"
