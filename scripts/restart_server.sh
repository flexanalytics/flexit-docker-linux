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

# Pull from the repo BEFORE tearing anything down. A failed pull — bad
# credentials, no network, a diverged checkout — then aborts with the stack
# still serving, instead of leaving the site down until someone intervenes.
#
# Git ops must NOT run as root. When this script (or deploy_server.sh
# upstream) is invoked via sudo, plain `git` would run as root and
# create root-owned objects under .git/objects/, which then poison the
# repo: subsequent non-sudo git operations fail with "insufficient
# permission for adding an object to repository database".
#
# When $SUDO_USER is set, drop back to the invoking user for every git
# call. Otherwise (run directly without sudo) just use `git`.
if [ -n "$SUDO_USER" ]; then
    git_cmd() { sudo -u "$SUDO_USER" git "$@"; }
else
    git_cmd() { git "$@"; }
fi

echo "Pulling changes from GitHub"
if ! git_cmd diff --quiet || ! git_cmd diff --cached --quiet || [ -n "$(git_cmd ls-files --others --exclude-standard)" ]; then
  git_cmd stash push -u -m "auto-stash before pull"
  STASHED=1
fi

git_cmd pull origin HEAD --ff-only

if [ "$STASHED" = "1" ]; then
  git_cmd stash pop
fi

# Also before teardown: the containers read the cert off disk when they
# start, so generating it early costs nothing and keeps an openssl failure
# out of the outage window.
if [[ "$USE_SELF_SIGNED_CERT" == "true" ]]; then
  echo "Checking renewal of self-signed cert"
  ./renew_certs.sh
fi

echo "Stopping and removing containers..."
./stop_server.sh

./start_server.sh
