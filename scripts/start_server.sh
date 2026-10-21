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

./check_env.sh

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
export FLEXIT_DEPLOY_TOKEN="${FLEXIT_DEPLOY_TOKEN:-}"
if ! sudo --preserve-env=FLEXIT_DEPLOY_TOKEN docker compose $COMPOSE_FILES build --build-arg CACHEBUST=$(date +%s); then
    echo "ERROR: build failed, FlexIt was NOT updated and is starting on the previous image." >&2
    if [ -z "$FLEXIT_DEPLOY_TOKEN" ]; then
        echo "ERROR: FLEXIT_DEPLOY_TOKEN is empty in .env; it is required to download private FlexIt releases." >&2
    else
        echo "ERROR: check that FLEXIT_DEPLOY_TOKEN in .env is valid and not expired, and that FLEXIT_VERSION exists." >&2
    fi
fi

# Set memory limit to available RAM minus 1G buffer (Linux only; on Mac, Docker Desktop manages this)
if [[ "$(uname)" == "Linux" ]]; then
    available_mb=$(free -m | awk '/^Mem:/{print $7}')
    # a running flexit container is about to be replaced, so its memory counts as available
    running_usage=$(sudo docker stats --no-stream --format '{{.MemUsage}}' flexit-analytics 2>/dev/null | awk '{print $1}' | sed 's/B$//')
    if [ -n "$running_usage" ]; then
        available_mb=$(( available_mb + $(numfmt --from=auto "$running_usage") / 1048576 ))
    fi
    export MEMORY_LIMIT=$(( available_mb - 1024 ))m
    echo "Setting container memory limit to $MEMORY_LIMIT"
fi

if [[ "$AUTO_MANAGE_CERTS" == "true" ]]; then
    ./scripts/renew_letsencrypt.sh
fi

# Start services; containers whose image or config changed are recreated in place
echo "Starting services with: sudo docker compose $COMPOSE_FILES up -d --remove-orphans $PULL_FLAG"
sudo --preserve-env=FLEXIT_DEPLOY_TOKEN docker compose $COMPOSE_FILES up -d --remove-orphans $PULL_FLAG

echo "Pruning unused docker artifacts"
sudo docker system prune -f
