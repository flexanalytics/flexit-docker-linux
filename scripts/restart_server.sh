#!/bin/bash

set -e  # Exit immediately if a command fails

# Change to script directory to ensure relative paths work
cd "$(dirname "$0")"

# Restart services
echo "Stopping and removing containers..."
./stop_server.sh

# Pull from the repo
echo "Pulling changes from GitHub"
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git stash push -u -m "auto-stash before pull"
  STASHED=1
fi

git pull origin HEAD --ff-only

if [ "$STASHED" = "1" ]; then
  git stash pop
fi

./start_server.sh
