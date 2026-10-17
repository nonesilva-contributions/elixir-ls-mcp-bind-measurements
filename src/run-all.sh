#!/usr/bin/env bash
# Runs every measurement of this repository and writes results/.
# Usage: src/run-all.sh <path to an elixir-ls clone>
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <elixir-ls clone>" >&2; exit 2; }
HERE=$(dirname "$0")
"$HERE/run-bind.sh" 27 28 29
"$HERE/run-listen-failure.sh" "$1" 1.18.4-otp-27 1.19.6-otp-28 1.20.4-otp-29
