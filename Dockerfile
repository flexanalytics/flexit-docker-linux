FROM ubuntu:jammy AS base

ENV DEBIAN_FRONTEND=noninteractive

# dlt verified sources to pre-install (space-separated)
# These are API sources that require dlt init (sql_database is built-in)
# Override at build time: --build-arg DLT_VERIFIED_SOURCES="salesforce hubspot"
ARG DLT_VERIFIED_SOURCES="filesystem"
# Per-install warehouse choice, passed from .env by docker-compose.yml.
# DBT_ADAPTERS is comma-separated; DLT_DEFAULT_DESTINATION is a dlt destination name.
ARG DBT_ADAPTERS=snowflake,redshift
ARG DLT_DEFAULT_DESTINATION=snowflake
ENV DLT_VERIFIED_SOURCES=${DLT_VERIFIED_SOURCES}
ENV DBT_ADAPTERS=${DBT_ADAPTERS}
ENV DLT_DEFAULT_DESTINATION=${DLT_DEFAULT_DESTINATION}

# Central location for dlt verified sources (accessible from any deployment folder)
ENV DLT_SOURCES_PATH=/opt/flexit/dlt_sources
ENV PYTHONPATH=${DLT_SOURCES_PATH}
ENV MIMALLOC_PURGE_DELAY=0

# Set working directory
WORKDIR /opt/flexit/bin

ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Every Python package version is pinned in constraints.txt; pip honors
# PIP_CONSTRAINT for each install below, dlt source requirements included
COPY constraints.txt /tmp/constraints.txt
ARG PIP_CONSTRAINT=/tmp/constraints.txt

# System packages, Python tooling and dlt sources share one layer so the
# build-essential purge and cache cleanup actually shrink the image
RUN apt-get update && apt-get install -y --no-install-recommends \
        apt-transport-https \
        build-essential \
        curl \
        git \
        gnupg \
        libaio1 \
        libgssapi-krb5-2 \
        libpq-dev \
        openssh-client \
        python3-venv \
        python3-pip \
        sudo \
        systemd \
        tini \
        unixodbc \
        unixodbc-dev \
    && python3 -m pip install --no-cache-dir --upgrade pip \
    # dbt with the adapters this install selected
    && python3 -m pip install --no-cache-dir \
        dbt-core \
        $(echo "${DBT_ADAPTERS}" | tr ',' '\n' | sed '/^ *$/d; s/^ *\(.*[^ ]\) *$/dbt-\1/') \
    # dlt with destination + source extras
    && python3 -m pip install --no-cache-dir \
        "dlt[${DLT_DEFAULT_DESTINATION},filesystem,s3,sftp,sql_database]" \
    # Database drivers for dlt sql_database source (not covered by destination extras)
    && python3 -m pip install --no-cache-dir \
        numpy \
        openpyxl \
        oracledb \
        psycopg2-binary \
        pymysql \
        pyodbc \
        pyarrow \
        pandas \
        sqlalchemy \
        snowflake-sqlalchemy \
    && python3 -m pip install --no-cache-dir dbt-colibri \
    # symlink python3 to python for convenience
    && ln -s /usr/bin/python3 /usr/local/bin/python \
    # Pre-install dlt verified sources to central location, importable via PYTHONPATH
    && mkdir -p ${DLT_SOURCES_PATH} \
    && cd ${DLT_SOURCES_PATH} \
    && for source in ${DLT_VERIFIED_SOURCES}; do \
        echo "Installing dlt verified source: ${source}"; \
        dlt init ${source} ${DLT_DEFAULT_DESTINATION}; \
        if [ -f requirements.txt ]; then \
            python3 -m pip install --no-cache-dir -r requirements.txt; \
        fi; \
    done \
    && rm -f ${DLT_SOURCES_PATH}/*.py \
    && apt-get purge -y build-essential \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache

# Use cache for everything except FlexIt install
# https://stackoverflow.com/questions/35134713/disable-cache-for-specific-run-commands
FROM base AS final

ARG CACHEBUST=1
ARG FLEXIT_VERSION=latest
RUN echo "$CACHEBUST"

# Attempt to copy the FlexIt installer if found locally
COPY flexit-linux-x64-installer.ru[n] /tmp/flexit-linux-x64-installer.run

# Check if the FlexIt installer exists locally; if not, download it
RUN \
    if [ ! -f /tmp/flexit-linux-x64-installer.run ]; then \
        if [ "$FLEXIT_VERSION" = "latest" ]; then \
            curl -fsSL -o flexit.run https://github.com/flexanalytics/flexit-deploy/releases/latest/download/flexit-linux-x64-installer.run; \
        else \
            curl -fsSL -o flexit.run https://github.com/flexanalytics/flexit-deploy/releases/download/${FLEXIT_VERSION}/flexit-linux-x64-installer.run; \
        fi; \
    else \
        mv /tmp/flexit-linux-x64-installer.run ./flexit.run; \
    fi \
    && chmod +x ./flexit.run \
    && ./flexit.run --mode unattended --unattendedmodeui none \
    && rm ./flexit.run

# Expose the application port
EXPOSE 3030

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

HEALTHCHECK --interval=30s --timeout=15s --start-period=600s --retries=3 \
    CMD curl -fs -o /dev/null http://localhost:3030/ || curl -fsk -o /dev/null https://localhost:3030/ || exit 1

# Use tini as the init system and start the application
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
