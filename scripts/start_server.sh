#!/bin/bash

set -e  # Exit immediately if a command fails

# Load environment variables from .env file if it exists
if [ -f ./.env ]; then
    export $(grep -v '^#' ./.env | xargs)
fi

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
echo "Starting services with: docker compose $COMPOSE_FILES up -d"
docker compose $COMPOSE_FILES up -d
