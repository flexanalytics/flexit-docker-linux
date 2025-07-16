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

cd ..

KEY_PATH="${CERT_PATH}/certificates/${PUBLIC_DNS}.key"
CRT_PATH="${CERT_PATH}/certificates/${PUBLIC_DNS}.crt"

# Renew if cert expires in < 30 days
if openssl x509 -checkend $(( 30 * 86400 )) -noout -in "$CRT_PATH"; then
  echo "[$(date)] Certificate is still valid. No renewal needed."
else
  echo "[$(date)] Renewing self-signed certificate..."
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$KEY_PATH" \
    -out "$CRT_PATH" \
    -subj "/CN=${PUBLIC_DNS}"

  echo "[$(date)] Restarting nginx container..."
  docker restart flexit-webserver
fi
