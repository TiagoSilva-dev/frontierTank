#!/bin/sh
# Godot does not act on SIGTERM, so `docker stop` would kill the server without saving.
# This wrapper turns the signal into a stop file the game server checks every second:
# it saves every profile, frees the accounts and quits by itself.
STOP_FILE="${FT_STOP_FILE:-/tmp/frontier-stop}"
rm -f "$STOP_FILE"
godot --headless --path /game -- --server "$@" &
PID=$!
trap 'touch "$STOP_FILE"' TERM INT
STATUS=0
while kill -0 "$PID" 2>/dev/null; do
	wait "$PID"
	STATUS=$?
done
exit "$STATUS"
