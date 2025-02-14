#!/bin/bash

set -e  # Exit immediately if a command fails

# Load environment variables from .env file if it exists
if [ -f ./.env ]; then
    export $(grep -v '^#' ./.env | xargs)
fi

# Determine which docker-compose files to use
COMPOSE_FILES="-f docker-compose.yml"

if [[ "$USE_NGINX" == "true" ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f docker-compose-proxy.yml"
fi

if [[ "$AUTO_MANAGE_CERTS" == "true" ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f docker-compose-webserver.yml"
fi

# Stop and remove services
echo "Stopping and removing containers with: docker compose $COMPOSE_FILES down --remove-orphans"
docker compose $COMPOSE_FILES down --remove-orphans
