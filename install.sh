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

ENV_CREATED=false
if [ ! -f .env ]; then
    cp .env.template .env
    chmod 600 .env
    [ -n "$SUDO_USER" ] && chown "$SUDO_USER" .env
    ENV_CREATED=true
    echo
    echo "Created .env from .env.template."
fi

env_value() {
    grep "^$1=" .env | cut -d '=' -f2- | tr -d "'\""
}

set_env_value() {
    local escaped
    escaped=$(printf '%s' "$2" | sed 's/[|&\\]/\\&/g')
    if grep -q "^$1=" .env; then
        sed -i "s|^$1=.*|$1='$escaped'|" .env
    else
        echo "$1='$2'" >> .env
    fi
}

ask() {
    local key=$1 prompt=$2 reply
    while true; do
        read -r -p "$prompt [$(env_value "$key")]: " reply
        if [[ "$reply" != *\'* ]]; then
            break
        fi
        echo "  Values cannot contain a single quote."
    done
    if [ -n "$reply" ]; then
        set_env_value "$key" "$reply"
    fi
}

ask_yes_no() {
    local key=$1 prompt=$2 hint reply
    if [ "$(env_value "$key")" = true ]; then hint="Y/n"; else hint="y/N"; fi
    read -r -p "$prompt [$hint] " reply
    case "$reply" in
        [Yy]*) set_env_value "$key" true ;;
        [Nn]*) set_env_value "$key" false ;;
    esac
}

# $4 = single rejects comma-separated lists
ask_choice() {
    local key=$1 prompt=$2 allowed=$3 mode=$4 reply item valid
    while true; do
        read -r -p "$prompt ($allowed) [$(env_value "$key")]: " reply
        reply=$(echo "$reply" | tr -d ' ')
        if [ -z "$reply" ]; then
            return 0
        fi
        valid=true
        if [ "$mode" = single ] && [[ "$reply" == *,* ]]; then
            valid=false
        fi
        for item in $(echo "$reply" | tr ',' ' '); do
            case " $allowed " in
                *" $item "*) ;;
                *) valid=false ;;
            esac
        done
        if [ "$valid" = true ]; then
            set_env_value "$key" "$reply"
            return 0
        fi
        if [ "$mode" = single ]; then
            echo "  Enter exactly one of: $allowed"
        else
            echo "  Use only these, separated by commas: $allowed"
        fi
    done
}

configure_env() {
    echo
    echo "Let's configure this install. Press Enter to keep the value shown in brackets."
    echo
    ask FLEXIT_VERSION "FlexIt version to install (a release number, or latest)"
    ask FLEXIT_PORT "Port FlexIt listens on"
    # keep in sync with scripts/check_env.sh
    ask_choice DBT_ADAPTERS "dbt adapters, comma-separated" "snowflake redshift postgres oracle"
    echo
    echo "dlt loads data into one destination. SQL database sources (Oracle, Postgres, MySQL, SQL Server, Snowflake) are always available."
    ask_choice DLT_DEFAULT_DESTINATION "dlt destination, pick one (sqlalchemy for Oracle)" "snowflake redshift postgres sqlalchemy" single
    ask DLT_VERIFIED_SOURCES "dlt verified API sources to pre-install, space-separated (e.g. filesystem salesforce)"
    echo
    ask DB_USER "Content database user"
    ask DB_NAME "Content database name"

    echo
    ask_yes_no USE_NGINX "Serve FlexIt over HTTPS through the bundled nginx?"
    if [ "$(env_value USE_NGINX)" = true ]; then
        ask PUBLIC_DNS "Public DNS name for this server"
        ask_yes_no AUTO_MANAGE_CERTS "Get and renew certificates automatically with Let's Encrypt?"
        if [ "$(env_value AUTO_MANAGE_CERTS)" = true ]; then
            ask CERT_EMAIL "Email for Let's Encrypt expiry notices"
        else
            ask_yes_no USE_SELF_SIGNED_CERT "Use a self-signed certificate (for testing)?"
            if [ "$(env_value USE_SELF_SIGNED_CERT)" != true ]; then
                ask CERT_PATH "Folder containing your certificate files"
            fi
        fi
    fi
}

if [ "$ENV_CREATED" = true ] && [ -t 0 ]; then
    configure_env
fi

offer_secret() {
    local key=$1
    shift
    [ -t 0 ] || return 0
    echo
    printf '%s\n' "$@"
    read -r -p "Generate a random value for $key now? [Y/n] " reply
    case "$reply" in
        [Nn]*) echo "Skipped. Set $key in .env yourself before rerunning." ;;
        *) set_env_value "$key" "$(openssl rand -hex 16)"; echo "Generated $key and saved it to .env." ;;
    esac
}

CURRENT_DB_PASSWORD=$(env_value DB_PASSWORD)
if [ -z "$CURRENT_DB_PASSWORD" ] || [ "$CURRENT_DB_PASSWORD" = "secure-password" ]; then
    offer_secret DB_PASSWORD \
        "DB_PASSWORD is the password FlexIt uses to connect to its own content database." \
        "Nothing outside this server needs it, so a random value is the safest choice."
fi

if [ -z "$(env_value FLEXIT_ENCRYPTION_KEY)" ]; then
    offer_secret FLEXIT_ENCRYPTION_KEY \
        "FLEXIT_ENCRYPTION_KEY encrypts the datasource and integration secrets FlexIt stores." \
        "If you are moving an existing install, answer n and copy that server's key into .env instead." \
        "Once set, never change or lose it: saved secrets cannot be recovered without it."
    if [ -n "$(env_value FLEXIT_ENCRYPTION_KEY)" ]; then
        echo
        echo "IMPORTANT: back up FLEXIT_ENCRYPTION_KEY from .env now, e.g. in your password manager."
    fi
fi

if [ "$ENV_CREATED" = true ] && [ ! -t 0 ]; then
    echo
    echo "Review the rest of .env before continuing:"
    echo "  - FLEXIT_VERSION, DBT_ADAPTERS, DLT_DEFAULT_DESTINATION"
    echo "  - nginx / cert settings if serving over HTTPS"
    echo "Then rerun: sudo ./install.sh"
    exit 1
fi

echo "Installing FlexIt..."
./scripts/start_server.sh

FLEXIT_PORT=$(env_value FLEXIT_PORT)
echo "Configure the application by navigating to http://localhost:$FLEXIT_PORT"

echo "Process completed successfully."
