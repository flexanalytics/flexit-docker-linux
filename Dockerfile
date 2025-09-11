FROM ubuntu:jammy AS base

ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables for FlexIt, Sling, and dbt versions
ENV FLEXIT_VERSION=latest
ENV SLING_VERSION=v1.4.5
ENV DBT_VERSION=1.9

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    build-essential \
    curl \
    git \
    gnupg \
    libgssapi-krb5-2 \
    python3-full \
    python3-pip \
    python3-venv \
    python3.11 \
    sudo \
    systemd \
    tini \
    unixodbc \
    unixodbc-dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /etc/apt/keyrings/google-linux.gpg \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list \
 && apt-get update && apt-get install -y --no-install-recommends \
    google-chrome-stable \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; cd /opt/google/chrome/locales; \
    find . -type f ! -name 'en-US.pak' -delete || true

ENV CHROMIUM_PATH=/usr/bin/google-chrome
ENV CHROME_FLAGS="--headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage"

# Set working directory
WORKDIR /opt/flexit/bin

# Install sling for data ingestion
RUN \
    curl -LO https://github.com/slingdata-io/sling-cli/releases/download/${SLING_VERSION}/sling_linux_amd64.tar.gz \
    && tar xf sling_linux_amd64.tar.gz -C /usr/local/bin \
    && rm -f sling_linux_amd64.tar.gz \
    && chmod +x /usr/local/bin/sling

# Install dbt
RUN \
    python3 -m venv venv \
    && . venv/bin/activate \
    && python3 -m pip install --no-cache-dir --upgrade pip \
    && python3 -m pip install --no-cache-dir \
        "dbt-core~=${DBT_VERSION}" \
        "dbt-redshift~=${DBT_VERSION}" \
    # symlink virtualenv dbt to a location on $PATH
    && ln -s /opt/flexit/bin/venv/bin/dbt /usr/local/bin/dbt

# Clean up
RUN \
    apt-get purge -y build-essential \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache

# Use cache for everything except FlexIt install
# https://stackoverflow.com/questions/35134713/disable-cache-for-specific-run-commands
FROM base AS final

ARG CACHEBUST=1
RUN echo "$CACHEBUST"

# Attempt to copy the FlexIt installer if found locally
COPY flexit-linux-x64-installer.ru[n] /tmp/flexit-linux-x64-installer.run

# Check if the FlexIt installer exists locally; if not, download it
RUN \
    if [ ! -f /tmp/flexit-linux-x64-installer.run ]; then \
        if [ "$FLEXIT_VERSION" = "latest" ]; then \
            curl -L -o flexit.run -C - https://github.com/flexanalytics/flexit-deploy/releases/latest/download/flexit-linux-x64-installer.run; \
        else \
            curl -L -o flexit.run -C - https://github.com/flexanalytics/flexit-deploy/releases/download/${FLEXIT_VERSION}/flexit-linux-x64-installer.run; \
        fi; \
    else \
        mv /tmp/flexit-linux-x64-installer.run ./flexit.run; \
    fi \
    && chmod +x ./flexit.run \
    && ./flexit.run --mode unattended --unattendedmodeui none \
    && rm ./flexit.run

# Expose the application port
EXPOSE 3030

# Use tini as the init system and start the application
ENTRYPOINT ["/usr/bin/tini", "--", "sh", "-c", "./start_flexit && tail -f /dev/null"]
