#!/bin/bash
#
# Refuses to proceed unless .env has been deliberately filled in from
# .env.template. Run before anything that starts or tears down the stack.

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "ERROR: .env not found. Copy the template and fill it in:" >&2
    echo "  cp .env.template .env" >&2
    exit 1
fi

set -a
source .env
set +a

ERRORS=()

for key in FLEXIT_PORT FLEXIT_VERSION DB_USER DB_PASSWORD DB_NAME DB_PORT; do
    [ -z "${!key}" ] && ERRORS+=("$key is empty")
done

[ "$DB_PASSWORD" = "secure-password" ] && ERRORS+=("DB_PASSWORD is still the template default")

if [ -z "$FLEXIT_ENCRYPTION_KEY" ]; then
    ERRORS+=("FLEXIT_ENCRYPTION_KEY is empty — generate one with: openssl rand -hex 16")
elif [ "${#FLEXIT_ENCRYPTION_KEY}" -ne 32 ]; then
    ERRORS+=("FLEXIT_ENCRYPTION_KEY must be 32 characters (got ${#FLEXIT_ENCRYPTION_KEY})")
fi

if [ "$USE_NGINX" = "true" ] || [ "$AUTO_MANAGE_CERTS" = "true" ] || [ "$USE_SELF_SIGNED_CERT" = "true" ]; then
    [ -z "$PUBLIC_DNS" ] || [ "$PUBLIC_DNS" = "a.example.com" ] && ERRORS+=("PUBLIC_DNS must be set to the server's domain")
    [ -z "$CERT_PATH" ] && ERRORS+=("CERT_PATH is empty")
fi

if [ "$AUTO_MANAGE_CERTS" = "true" ]; then
    [ -z "$CERT_EMAIL" ] || [ "$CERT_EMAIL" = "email@site.com" ] && ERRORS+=("CERT_EMAIL must be a real address for Let's Encrypt")
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "ERROR: .env is not ready for deploy:" >&2
    for e in "${ERRORS[@]}"; do
        echo "  - $e" >&2
    done
    exit 1
fi

echo ".env check passed"
