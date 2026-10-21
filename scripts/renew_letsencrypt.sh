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

# lego answers the TLS challenge on 443, so nginx has to let go of it first
WEBSERVER_STOPPED=0
if sudo docker ps --format '{{.Names}}' | grep -q "^flexit-webserver$"; then
    sudo docker stop flexit-webserver
    WEBSERVER_STOPPED=1
fi

# A one-off lego failure must not abort the deploy — that leaves the stack
# down and the auto-deploy marker unreachable, so cron can never retry.
FAIL_STATE="${CERT_PATH}/.renew_failures"
CERT_RENEW_MAX_FAILURES=${CERT_RENEW_MAX_FAILURES:-3}
if sudo docker compose -f docker-compose-proxy.yml up --abort-on-container-exit; then
    sudo rm -f "$FAIL_STATE"
else
    FAILURES=$(sudo cat "$FAIL_STATE" 2>/dev/null || echo 0)
    case "$FAILURES" in ''|*[!0-9]*) FAILURES=0 ;; esac
    FAILURES=$((FAILURES + 1))
    echo "$FAILURES" | sudo tee "$FAIL_STATE" >/dev/null
    # lego only attempts a renewal inside its 30-day window, so repeated
    # failures mean the cert is actually running out. Go loud.
    if [ "$FAILURES" -ge "$CERT_RENEW_MAX_FAILURES" ]; then
        echo "ERROR: certificate renewal has failed $FAILURES times in a row — the cert is inside its renewal window and not renewing. Aborting." >&2
        if [ "$WEBSERVER_STOPPED" = "1" ]; then
            sudo docker start flexit-webserver
        fi
        exit 1
    fi
    echo "WARNING: certificate renewal failed ($FAILURES/$CERT_RENEW_MAX_FAILURES); continuing with the existing certificate" >&2
fi
