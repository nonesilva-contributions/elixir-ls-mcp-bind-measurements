#!/usr/bin/env bash
# Runs src/listen-failure-in-container.sh in each elixir image, as a user that is not root.
# Ports below 1024 need root, so a listen on port 80 fails there.
# Usage: src/run-listen-failure.sh <path to an elixir-ls clone> <elixir image tag>...
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: $0 <elixir-ls clone> <elixir image tag>..." >&2; exit 2; }
SRC=$(cd "$1" && pwd); shift
cd "$(dirname "$0")/.."
mkdir -p results
for TAG in "$@"; do
  OUT="results/listen-failure-elixir-$TAG.txt"
  echo "== elixir:$TAG -> $OUT"
  docker run --rm --name "elx-meas-lf-$TAG" --user 1000:1000 \
    --sysctl net.ipv4.ip_unprivileged_port_start=1024 \
    -e HOME=/tmp/home -e MASTER=68df44b681ee0dbef91b8008b0354003a9a451fa -e TAG="$TAG" \
    -v "$SRC:/src:ro" -v "$PWD:/meas:ro" \
    "elixir:$TAG" bash /meas/src/listen-failure-in-container.sh > "$OUT" 2>&1 || true
  cat "$OUT"
  grep -q '^done$' "$OUT"
done
