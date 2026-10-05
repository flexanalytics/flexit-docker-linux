#!/bin/bash

set -e

cd "$(dirname "$0")"

echo "Welcome to the FlexIt installation setup. This will install the needed tools and allow you to configure the application."
sleep 1.5

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo "Docker is already installed. Skipping installation."
else
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Ensure Docker service is running
    sudo systemctl enable --now docker
fi

if [ ! -f .env ]; then
    cp .env.template .env
    chmod 600 .env
    [ -n "$SUDO_USER" ] && chown "$SUDO_USER" .env
    echo
    echo "Created .env from .env.template. Fill it in before continuing:"
    echo "  - DB_USER / DB_PASSWORD / DB_NAME"
    echo "  - FLEXIT_ENCRYPTION_KEY (generate with: openssl rand -hex 16)"
    echo "  - nginx / cert settings if serving over HTTPS"
    echo "Then rerun: sudo ./install.sh"
    exit 1
fi

echo "Installing FlexIt..."
./scripts/start_server.sh

FLEXIT_PORT=$(grep '^FLEXIT_PORT=' .env | cut -d '=' -f2)
echo "Configure the application by navigating to http://localhost:$FLEXIT_PORT"

echo "Process completed successfully."
