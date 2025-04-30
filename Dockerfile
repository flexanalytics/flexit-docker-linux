
FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables for FlexIt, Sling, and dbt versions
ARG FLEXIT_VERSION=2025.04.005
ENV FLEXIT_VERSION=$FLEXIT_VERSION

ARG SLING_VERSION=v1.2.13
ENV SLING_VERSION=$SLING_VERSION

ARG DBT_VERSION=1.9
ENV DBT_VERSION=$DBT_VERSION

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    build-essential \
    chromium-browser \
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

# Set working directory
WORKDIR /opt/flexit/bin

# Attempt to copy the FlexIt installer if found locally
COPY flexit-linux-x64-installer.ru[n] /tmp/flexit-linux-x64-installer.run

# Check if the FlexIt installer exists locally; if not, download it
RUN \
    if [ ! -f /tmp/flexit-linux-x64-installer.run ]; then \
        curl -L -o flexit.run -C - https://github.com/flexanalytics/flexit-deploy/releases/download/${FLEXIT_VERSION}/flexit-linux-x64-installer.run; \
    else \
        mv /tmp/flexit-linux-x64-installer.run ./flexit.run; \
    fi \
    && chmod +x ./flexit.run \
    && ./flexit.run --mode unattended --unattendedmodeui none \
    && rm ./flexit.run

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
        "dbt-snowflake~=${DBT_VERSION}" \
        "dbt-bigquery~=${DBT_VERSION}" \
    # symlink virtualenv dbt to a location on $PATH
    && ln -s /opt/flexit/bin/venv/bin/dbt /usr/local/bin/dbt

# Clean up
RUN \
    apt-get purge -y build-essential \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache

# Expose the application port
EXPOSE 3030

# Use tini as the init system and start the application
ENTRYPOINT ["/usr/bin/tini", "--", "sh", "-c", "./start_flexit && tail -f /dev/null"]
