#!/bin/bash

set -e

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

# Prompt for database details
echo "Please configure the backend database. Keep these credentials secure, you will only be asked once."
read -p "Enter database username: " DB_USER
read -s -p "Enter database password: " DB_PASSWORD
echo
read -p "Enter database name: " DB_NAME

# Export environment variables
echo "Exporting environment variables..."
export POSTGRES_USER="$DB_USER"
export POSTGRES_PASSWORD="$DB_PASSWORD"
export POSTGRES_DB="$DB_NAME"
export DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@flexit-content-database:5432/$DB_NAME"

echo "Installing FlexIt..."
docker compose up -d --build

# Retrieve FLEXIT_PORT from .env file
if [ -f .env ]; then
    FLEXIT_PORT=$(grep '^FLEXIT_PORT=' .env | cut -d '=' -f2)
    echo "Configure the application by navigating to http://localhost:$FLEXIT_PORT"
else
    echo "No .env file found. Please configure your application manually."
fi

echo "Process completed successfully."


