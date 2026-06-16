#!/bin/bash
#
# Cron-friendly wrapper around deploy_server.sh. Runs the deploy only when
# Flexit's UI has written a "ready" marker; otherwise no-ops. The marker
# lives inside the named docker volume flexit_webcontent — we use
# `docker exec` to read it rather than a host bind-mount path.
#
# Crontab entry (1 min poll is typical):
#   * * * * * /path/to/scripts/auto_deploy_server.sh >> /var/log/flexit-deploy.log 2>&1
#
# Behavior:
#   - container not running    → exit 0 silently (nothing to deploy yet)
#   - marker absent            → exit 0 silently
#   - marker present, !ready   → exit 0 silently
#   - marker present, ready    → run deploy_server.sh
#   - already deploying        → exit 0 (lock-protected)
#
# After deploy, the marker is NOT cleared by this script. The new Flexit
# clears it during boot-reconcile (see server/boot/deploy-reconcile.js in
# the flexit repo) — this avoids a race where the host deletes the marker
# before the new container's Flexit has a chance to read it for the audit.

set -e

cd "$(dirname "$0")"

CONTAINER_NAME=flexit-analytics
MARKER=/opt/flexit/webcontent/.deploy_request
# Per-uid lock path so root-cron and user-test invocations don't collide on
# a 0644 file owned by whoever got there first. Doesn't compromise the lock
# semantics — concurrent ticks of the *same* user (which is what cron does)
# still serialize correctly.
LOCK=/tmp/flexit-auto-deploy.$(id -u).lock

# Decide how to invoke docker. Honors $DOCKER env override; otherwise
# tries plain `docker` (root cron, docker-group member, or rootless),
# then non-interactive sudo (passwordless sudo configured), then bails
# with a clear error so cron logs explain the problem.
detect_docker() {
    if [ -n "${DOCKER:-}" ]; then
        echo "$DOCKER"; return
    fi
    if docker info >/dev/null 2>&1; then
        echo "docker"; return
    fi
    if sudo -n docker info >/dev/null 2>&1; then
        echo "sudo docker"; return
    fi
    echo "ERROR: cannot access docker. Options:" >&2
    echo "  - install this cron via 'sudo crontab -e' so it runs as root" >&2
    echo "  - add your user to the docker group: usermod -aG docker \$USER" >&2
    echo "  - configure passwordless sudo for the docker binary" >&2
    echo "  - export DOCKER=\"<custom command>\" in your .env" >&2
    exit 1
}
DOCKER=$(detect_docker)

# Bail quickly if container isn't running — no Flexit means no UI to have
# requested anything. Keep this silent so the log doesn't grow during
# container outages.
if ! $DOCKER ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

# Marker check via docker exec. Both calls return non-zero (and produce no
# output) when the marker isn't present or isn't ready — the silent exit
# keeps cron logs clean.
if ! $DOCKER exec "$CONTAINER_NAME" test -f "$MARKER" 2>/dev/null; then
    exit 0
fi
if ! $DOCKER exec "$CONTAINER_NAME" grep -q '"status": *"ready"' "$MARKER" 2>/dev/null; then
    exit 0
fi

# Concurrent-tick protection. Long-running deploys must not race with the
# next cron tick if it fires before we finish. flock -n is non-blocking;
# if another instance owns the lock we bail quietly.
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy already in progress; skipping"
    exit 0
fi

echo "============================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: marker found, status=ready"
echo "Marker payload:"
$DOCKER exec "$CONTAINER_NAME" cat "$MARKER"
echo
echo "============================================================"

# Load .env so AUTO_DEPLOY_FAIL_BEHAVIOR (and anything else) is available.
if [ -f ../.env ]; then
    set -a
    source ../.env
    set +a
fi

DEPLOY_RC=0
./deploy_server.sh || DEPLOY_RC=$?

if [ $DEPLOY_RC -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: success"
    echo "Marker will be cleared by the new Flexit on boot-reconcile."
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: FAILED with exit code $DEPLOY_RC"
    # Deploy failed — the container may or may not be up. If the marker is
    # still reachable AND fail-mode says "clear", drop it so we don't loop.
    # Default: leave it alone for the next tick to retry.
    if [ "${AUTO_DEPLOY_FAIL_BEHAVIOR:-retry}" = "clear" ]; then
        $DOCKER ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" \
            && $DOCKER exec "$CONTAINER_NAME" rm -f "$MARKER" \
            && echo "AUTO_DEPLOY_FAIL_BEHAVIOR=clear — marker removed."
    else
        echo "Marker left in place; next cron tick will retry. Set AUTO_DEPLOY_FAIL_BEHAVIOR=clear in .env to disable retry."
    fi
    exit $DEPLOY_RC
fi
