#!/bin/bash

set -e  # Exit immediately if a command fails
# Stop and remove services
echo "Stopping and removing containers with: docker compose down --remove-orphans"
docker compose down --remove-orphans


