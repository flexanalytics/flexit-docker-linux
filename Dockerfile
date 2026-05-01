FROM ubuntu:jammy AS base

ENV DEBIAN_FRONTEND=noninteractive

# Set environment variables for FlexIt, Sling, dbt, and dlt versions
ENV FLEXIT_VERSION=latest
ENV DBT_VERSION=1.9
ENV DLT_VERSION=1.20

# dlt verified sources to pre-install (space-separated)
# These are API sources that require dlt init (sql_database is built-in)
# Override at build time: --build-arg DLT_VERIFIED_SOURCES="salesforce hubspot"
ARG DLT_VERIFIED_SOURCES="filesystem"
ARG DLT_DEFAULT_DESTINATION=snowflake
ENV DLT_VERIFIED_SOURCES=${DLT_VERIFIED_SOURCES}
ENV DLT_DEFAULT_DESTINATION=${DLT_DEFAULT_DESTINATION}

# Central location for dlt verified sources (accessible from any deployment folder)
ENV DLT_SOURCES_PATH=/opt/flexit/dlt_sources
ENV PYTHONPATH="${DLT_SOURCES_PATH}:${PYTHONPATH}"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    build-essential \
    curl \
    git \
    gnupg \
    libaio1 \
    libgssapi-krb5-2 \
    libpq-dev \
    python3-full \
    python3-pip \
    python3.11 \
    sudo \
    systemd \
    tini \
    unixodbc \
    unixodbc-dev

# Set working directory
WORKDIR /opt/flexit/bin

# Install dbt, dlt, and colibri (global install - no venv needed in Docker)
ENV PIP_BREAK_SYSTEM_PACKAGES=1
RUN \
    python3 -m pip install --no-cache-dir --upgrade pip \
    # dbt with adapters
    && python3 -m pip install --no-cache-dir \
        "dbt-core~=${DBT_VERSION}" \
        "dbt-redshift~=${DBT_VERSION}" \
    # dlt with destination + source extras
    && python3 -m pip install --no-cache-dir \
        "dlt[${DLT_DEFAULT_DESTINATION},filesystem,s3,sftp]~=${DLT_VERSION}" \
    # Database drivers for dlt sql_database source (not covered by destination extras)
    && python3 -m pip install --no-cache-dir \
        numpy \
        openpyxl \
        oracledb \
        pymysql \
        pyodbc \
        pyarrow \
        pandas \
    && python3 -m pip install --no-cache-dir dbt-colibri \
    # symlink python3 to python for convenience
    && ln -s /usr/bin/python3 /usr/local/bin/python

# Pre-install dlt verified sources to central location
# These can be imported from any deployment folder via PYTHONPATH
RUN \
    mkdir -p ${DLT_SOURCES_PATH} \
    && cd ${DLT_SOURCES_PATH} \
    && for source in ${DLT_VERIFIED_SOURCES}; do \
        echo "Installing dlt verified source: ${source}"; \
        dlt init ${source} ${DLT_DEFAULT_DESTINATION}; \
        if [ -f requirements.txt ]; then \
            python3 -m pip install --no-cache-dir -r requirements.txt; \
        fi; \
    done \
    && rm -f ${DLT_SOURCES_PATH}/*.py

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
