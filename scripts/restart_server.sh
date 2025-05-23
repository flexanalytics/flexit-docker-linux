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

# Restart services
echo "Stopping and removing containers..."
./stop_server.sh

# Pull from the repo
echo "Pulling changes from GitHub"
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git stash push -u -m "auto-stash before pull"
  STASHED=1
fi

git pull origin HEAD --ff-only

if [ "$STASHED" = "1" ]; then
  git stash pop
fi

./start_server.sh
