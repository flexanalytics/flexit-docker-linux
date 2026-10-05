#!/bin/bash
#
# start_flexit daemonizes, so this stays in the foreground as a watchdog:
# it exits non-zero when FlexIt stops answering, letting the restart policy
# recover the container, and shuts FlexIt down cleanly on docker stop.

cd /opt/flexit/bin

HEALTH_INTERVAL=${HEALTH_INTERVAL:-30}
HEALTH_MAX_FAILURES=${HEALTH_MAX_FAILURES:-5}
# Failures don't count until FlexIt first answers or this many seconds pass.
HEALTH_START_GRACE=${HEALTH_START_GRACE:-600}

healthy() {
    curl -fs -o /dev/null --max-time 10 http://localhost:3030/ \
        || curl -fsk -o /dev/null --max-time 10 https://localhost:3030/
}

shutdown() {
    echo "Stopping FlexIt..."
    sudo ./flexit kill
    sudo su postgres -c "$PWD/../pgsql/bin/pg_ctl stop -D $PWD/../pgsql/data -m fast" || true
    exit 0
}
trap shutdown TERM INT

./start_flexit || exit 1

started=0
failures=0
while true; do
    sleep "$HEALTH_INTERVAL" & wait $!
    if healthy; then
        started=1
        failures=0
    elif [ "$started" -eq 1 ] || [ "$SECONDS" -ge "$HEALTH_START_GRACE" ]; then
        failures=$((failures + 1))
        echo "FlexIt health check failed ($failures/$HEALTH_MAX_FAILURES)"
        if [ "$failures" -ge "$HEALTH_MAX_FAILURES" ]; then
            echo "FlexIt unresponsive, exiting so the container restarts" >&2
            exit 1
        fi
    fi
done
