#!/usr/bin/env bash
# Runs mcp_bind.erl in the official erlang:<version> images, on the default bridge network of Docker.
# Each container has its own network namespace. The host firewall rules do not apply there, and it has a non-loopback address, 172.17.0.x, to connect from.
# Usage: src/run-bind.sh 27 28 29
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -gt 0 ] || { echo "usage: $0 <otp-version>..." >&2; exit 2; }
mkdir -p results
for V in "$@"; do
  OUT="results/bind-erlang-$V.txt"
  echo "== erlang:$V, bridge network -> $OUT"
  docker run --rm --name "elx-meas-otp$V" -e IMAGE="erlang:$V" -v "$PWD/src/mcp_bind.erl:/mcp_bind.erl:ro" "erlang:$V" \
    sh -c 'cd /tmp && erlc /mcp_bind.erl && erl -noshell -pa /tmp -eval "mcp_bind:main()."' 2>&1 | tee "$OUT"
done
