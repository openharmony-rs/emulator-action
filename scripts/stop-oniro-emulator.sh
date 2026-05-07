#!/usr/bin/env bash
#
# Stop the Oniro emulator started via start-oniro-emulator.sh.

set -euo pipefail

pid_file="/tmp/oniro-emulator.pid"
connect_file="/tmp/oniro-emulator.connect"

if [ ! -f "$pid_file" ]; then
  echo "Error: emulator pid file not found at $pid_file." >&2
  echo "If the emulator is still running, stop the qemu process manually." >&2
  exit 1
fi

emulator_pid="$(cat "$pid_file")"

if ! kill -0 "$emulator_pid" >/dev/null 2>&1; then
  echo "Emulator process $emulator_pid is not running. Removing stale pid file."
  rm -f "$pid_file" "$connect_file"
  exit 0
fi

echo "Stopping Oniro emulator process $emulator_pid..."
kill -TERM "$emulator_pid" >/dev/null 2>&1 || true

for _ in $(seq 1 10); do
  if ! kill -0 "$emulator_pid" >/dev/null 2>&1; then
    rm -f "$pid_file" "$connect_file"
    echo "Oniro emulator stopped."
    exit 0
  fi
  sleep 1
done

echo "Emulator did not exit after SIGTERM. Sending SIGKILL." >&2
kill -KILL "$emulator_pid" >/dev/null 2>&1 || true
rm -f "$pid_file" "$connect_file"
echo "Oniro emulator stopped."
