#!/bin/bash

set -e  # Exit immediately if a command fails

# Start services
echo "Starting services with: docker compose up -d"
docker compose up -d

