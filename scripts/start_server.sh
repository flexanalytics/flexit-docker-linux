#!/bin/bash

set -e  # Exit immediately if a command fails

# Change to script directory to ensure relative paths work
cd "$(dirname "$0")"

# Load environment variables from .env file one directory up if it exists
if [ -f ../.env ]; then
    set -a
    source ../.env
    set +a
fi

cd ..

# Determine which docker-compose files to use
COMPOSE_FILES="-f docker-compose.yml"

if [[ "$USE_NGINX" == "true" ]]; then
    echo "Enabling Nginx (USE_NGINX=true)"
    COMPOSE_FILES="$COMPOSE_FILES -f docker-compose-webserver.yml"
fi

# # Should we pull the latest images or use a local patch?
# if "$RUN_PATCH"; then
#     PULL_FLAG="--pull missing"
# fi

# Build images
echo "Building local images"
if ! sudo docker compose $COMPOSE_FILES build --build-arg CACHEBUST=$(date +%s); then
    echo "Build failed, continuing with existing images"
fi

# Start services
echo "Starting services with: sudo docker compose $COMPOSE_FILES up -d $PULL_FLAG"
sudo docker compose $COMPOSE_FILES up -d $PULL_FLAG

echo "Pruning unused docker artifacts"
sudo docker system prune -f
