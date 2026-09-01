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
#   - container not running    → exit 0 silently, unless a retry is owed
#   - marker absent            → exit 0 silently
#   - marker present, !ready   → exit 0 silently
#   - marker present, ready    → run deploy_server.sh
#   - already deploying        → exit 0 (lock-protected)
#   - retry owed               → run deploy_server.sh even with the stack down
#   - new commit on $GIT_DEPLOY_BRANCH → run deploy_server.sh
#
# The git trigger is the out-of-band path: push to the deploy branch and the
# next tick deploys, no SSH needed. Unset GIT_DEPLOY_BRANCH disables it.
#
# A deploy that fails after teardown leaves the marker sealed inside a stopped
# container, so the in-container check alone can never see it again. $RETRY_STATE
# is the host-side record of a deploy still owed, capped at $AUTO_DEPLOY_MAX_ATTEMPTS.
#
# After deploy, the marker is NOT cleared by this script. The new Flexit
# clears it during boot-reconcile (see server/boot/deploy-reconcile.js in
# the flexit repo) — this avoids a race where the host deletes the marker
# before the new container's Flexit has a chance to read it for the audit.

set -e

cd "$(dirname "$0")"

# Loaded up front so DOCKER and the AUTO_DEPLOY_* knobs apply to every branch
# below, detect_docker included.
if [ -f ../.env ]; then
    set -a
    source ../.env
    set +a
fi

CONTAINER_NAME=flexit-analytics
MARKER=/opt/flexit/webcontent/.deploy_request
# Per-uid lock path so root-cron and user-test invocations don't collide on
# a 0644 file owned by whoever got there first. Doesn't compromise the lock
# semantics — concurrent ticks of the *same* user (which is what cron does)
# still serialize correctly.
LOCK=/tmp/flexit-auto-deploy.$(id -u).lock
# Host-side, so it stays readable when the container it describes is gone.
# Reboot clears it, which is fine: the stack comes back and the marker is live again.
RETRY_STATE=/tmp/flexit-auto-deploy-retry.$(id -u).state
MAX_ATTEMPTS=${AUTO_DEPLOY_MAX_ATTEMPTS:-5}

# Branch watched for the git trigger; empty disables it entirely.
GIT_DEPLOY_BRANCH=${GIT_DEPLOY_BRANCH:-}
# Survives reboots, unlike $RETRY_STATE — a pushed commit must not be forgotten.
STATE_DIR=${AUTO_DEPLOY_STATE_DIR:-/var/lib/flexit}
HANDLED_SHA_FILE="$STATE_DIR/last_handled_sha"

# Git must never run as root against a user-owned checkout: root-owned objects
# under .git break every later non-sudo git call.
GIT_USER=""
if [ -n "${SUDO_USER:-}" ]; then
    GIT_USER="$SUDO_USER"
elif [ "$(id -u)" -eq 0 ]; then
    GIT_USER=$(stat -c '%U' ../.git 2>/dev/null || echo root)
fi
if [ -n "$GIT_USER" ] && [ "$GIT_USER" != "root" ]; then
    git_cmd() { sudo -u "$GIT_USER" git "$@"; }
else
    git_cmd() { git "$@"; }
fi

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

CONTAINER_UP=0
if $DOCKER ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    CONTAINER_UP=1
fi

ATTEMPTS=0
if [ -f "$RETRY_STATE" ]; then
    ATTEMPTS=$(cat "$RETRY_STATE" 2>/dev/null || echo 0)
    case "$ATTEMPTS" in ''|*[!0-9]*) ATTEMPTS=0 ;; esac
fi

# Git trigger. Compares the tip of the deploy branch against the last revision
# this script finished acting on — deployed or given up on.
GIT_TRIGGER=0
REMOTE_SHA=""
# The state dir is normally root-owned; a non-root run should skip the git
# trigger rather than die and take the marker path down with it.
if [ -n "$GIT_DEPLOY_BRANCH" ]; then
    if ! mkdir -p "$STATE_DIR" 2>/dev/null || [ ! -w "$STATE_DIR" ]; then
        echo "WARNING: $STATE_DIR not writable by $(id -un) — git trigger skipped. Create it once with: sudo mkdir -p $STATE_DIR" >&2
        GIT_DEPLOY_BRANCH=""
    fi
fi

if [ -n "$GIT_DEPLOY_BRANCH" ]; then
    # ls-remote is a single ref query — no object negotiation, so the steady
    # state of polling every minute stays cheap. The pull happens at deploy time.
    REMOTE_SHA=$(git_cmd ls-remote origin "refs/heads/$GIT_DEPLOY_BRANCH" 2>/dev/null | awk '{print $1}')
    if [ -n "$REMOTE_SHA" ]; then
        if [ ! -f "$HANDLED_SHA_FILE" ]; then
            # First run adopts the current revision rather than deploying on install.
            echo "$REMOTE_SHA" > "$HANDLED_SHA_FILE"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: baselined $GIT_DEPLOY_BRANCH at $REMOTE_SHA"
        elif [ "$REMOTE_SHA" != "$(cat "$HANDLED_SHA_FILE")" ]; then
            GIT_TRIGGER=1
        fi
    fi
fi

if [ "$GIT_TRIGGER" -eq 1 ]; then
    : # New revision on the deploy branch — deploy regardless of marker or stack state.
elif [ "$CONTAINER_UP" -eq 1 ]; then
    # Marker check via docker exec. Both calls return non-zero (and produce no
    # output) when the marker isn't present or isn't ready — the silent exit
    # keeps cron logs clean. Reaching here healthy also retires a stale retry.
    if ! $DOCKER exec "$CONTAINER_NAME" test -f "$MARKER" 2>/dev/null \
       || ! $DOCKER exec "$CONTAINER_NAME" grep -q '"status": *"ready"' "$MARKER" 2>/dev/null; then
        rm -f "$RETRY_STATE"
        exit 0
    fi
elif [ "$ATTEMPTS" -eq 0 ]; then
    # Stack is down and nothing is owed — not this script's problem. Silent so
    # the log doesn't grow during container outages.
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
if [ "$GIT_TRIGGER" -eq 1 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: new revision on $GIT_DEPLOY_BRANCH — $REMOTE_SHA"
elif [ "$CONTAINER_UP" -eq 1 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: marker found, status=ready"
    echo "Marker payload:"
    $DOCKER exec "$CONTAINER_NAME" cat "$MARKER"
    echo
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: retrying owed deploy (attempt $((ATTEMPTS + 1))/$MAX_ATTEMPTS); container is down, marker unreadable"
fi
echo "============================================================"

DEPLOY_RC=0
./deploy_server.sh || DEPLOY_RC=$?

if [ $DEPLOY_RC -eq 0 ]; then
    rm -f "$RETRY_STATE"
    if [ -n "$REMOTE_SHA" ]; then
        echo "$REMOTE_SHA" > "$HANDLED_SHA_FILE"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: success"
    echo "Marker will be cleared by the new Flexit on boot-reconcile."
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-deploy: FAILED with exit code $DEPLOY_RC"
    # Deploy failed — the container may or may not be up. If the marker is
    # still reachable AND fail-mode says "clear", drop it so we don't loop.
    # Default: leave it alone for the next tick to retry.
    if [ "${AUTO_DEPLOY_FAIL_BEHAVIOR:-retry}" = "clear" ]; then
        rm -f "$RETRY_STATE"
        $DOCKER ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" \
            && $DOCKER exec "$CONTAINER_NAME" rm -f "$MARKER" \
            && echo "AUTO_DEPLOY_FAIL_BEHAVIOR=clear — marker removed."
    else
        ATTEMPTS=$((ATTEMPTS + 1))
        if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
            rm -f "$RETRY_STATE"
            # Record the revision so the git trigger stops re-firing on it too;
            # pushing a new commit is what restarts the cycle.
            if [ -n "$REMOTE_SHA" ]; then
                echo "$REMOTE_SHA" > "$HANDLED_SHA_FILE"
            fi
            echo "auto-deploy: giving up after $ATTEMPTS failed attempts — manual intervention required. Raise AUTO_DEPLOY_MAX_ATTEMPTS in .env to retry longer."
        else
            echo "$ATTEMPTS" > "$RETRY_STATE"
            echo "Retry $ATTEMPTS/$MAX_ATTEMPTS owed; next cron tick will retry even if the container stays down."
        fi
    fi
    exit $DEPLOY_RC
fi
