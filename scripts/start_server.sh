#!/bin/bash

set -e  # Exit immediately if a command fails

# Change to script directory to ensure relative paths work
cd "$(dirname "$0")"

# Load environment variables from .env file one directory up if it exists
if [ -f ../.env ]; then
    export $(grep -v '^#' ../.env | xargs)
fi

cd ..

# Determine which docker-compose files to use
COMPOSE_FILES="-f docker-compose.yml"

if [[ "$USE_NGINX" == "true" ]]; then
    echo "Enabling Nginx (USE_NGINX=true)"
    COMPOSE_FILES="$COMPOSE_FILES -f docker-compose-proxy.yml"
fi

if [[ "$AUTO_MANAGE_CERTS" == "true" ]]; then
    echo "Enabling Automatic Certificate Management (AUTO_MANAGE_CERTS=true)"
    COMPOSE_FILES="$COMPOSE_FILES -f docker-compose-webserver.yml"
fi

# Start services
echo "Starting services with: sudo docker compose $COMPOSE_FILES up -d $PULL_FLAG"
sudo docker compose $COMPOSE_FILES up -d $PULL_FLAG
