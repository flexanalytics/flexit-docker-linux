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
    COMPOSE_FILES="$COMPOSE_FILES -f docker-compose-webserver.yml"
fi

# Stop and remove services
echo "Stopping and removing containers with: docker compose $COMPOSE_FILES down --remove-orphans"
sudo docker compose $COMPOSE_FILES down --remove-orphans

if [[ "$AUTO_MANAGE_CERTS" == "true" ]]; then
    sudo docker compose -f docker-compose-proxy.yml up --abort-on-container-exit
fi
