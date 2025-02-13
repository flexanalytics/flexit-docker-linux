#!/bin/bash

set -e  # Exit immediately if a command fails
# Restart services
echo "Stopping and removing containers..."
docker compose down --remove-orphans

echo "Restarting services with: docker compose up -d"
docker compose up -d


