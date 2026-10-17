#!/usr/bin/env bash
# Runs inside the elixir image, as src/run-listen-failure.sh starts it, and prints one result file.
# MASTER is the elixir-ls commit to measure, and TAG is the image tag.
set -euo pipefail
mkdir -p "$HOME"
git config --global --add safe.directory "*"
git clone -q /src /tmp/els && cd /tmp/els && git checkout -q "$MASTER"
mix local.hex --force >/dev/null && mix local.rebar --force >/dev/null && mix deps.get >/dev/null 2>&1
cp /meas/src/listen_failure_test.exs apps/language_server/test/listen_failure_probe_test.exs

root=$(elixir -e 'IO.write(:code.root_dir())')
otp=$(cat "$root/releases/$(elixir -e 'IO.write(System.otp_release())')/OTP_VERSION")
echo "environment"
echo "  image: elixir:$TAG"
echo "  Elixir $(elixir -e 'IO.write(System.version())'), OTP $otp, erts $(elixir -e 'IO.write(:erlang.system_info(:version))')"
echo "  user $(id -u), not root: a listen on a port below 1024 fails"

: > /tmp/all.txt
probe() {
  local version=$1 base=$2 expected=$3
  if ! (cd apps/language_server && VERSION=$version CASE_BASE=$base EXPECTED_PORT_80=$expected \
        mix test --seed 0 test/listen_failure_probe_test.exs > /tmp/out.txt 2>&1); then
    echo "  MISMATCH: the $version run failed" >> /tmp/all.txt
  fi
  grep -E '^(## [0-9]+\.|  -> |  MISMATCH)' /tmp/out.txt >> /tmp/all.txt || true
}
probe master 0 down
git apply /meas/patches/0001-Bind-the-MCP-server-to-loopback.patch
probe patch 2 alive

ok5=match
(cd apps/language_server && mix test --seed 0 test/mcp/ > /tmp/out.txt 2>&1) || ok5=MISMATCH
{
  echo "## 5. patch, mix test test/mcp/"
  printf '  -> %-34s -> %s\n' "tests" "$(grep -oE '[0-9]+ tests?, [0-9]+ failures?|Result: .*' /tmp/out.txt | tail -1)"
} >> /tmp/all.txt
awk '/^## /{print ""} {print}' /tmp/all.txt

verdicts=()
for n in 1 2 3 4; do
  if grep -q "^## $n\." /tmp/all.txt && ! grep -q "MISMATCH case $n:" /tmp/all.txt; then v=match; else v=MISMATCH; fi
  verdicts+=("case $n $v")
done
verdicts+=("case 5 $ok5")
echo
echo "summary: $(IFS=,; echo "${verdicts[*]}" | sed 's/,/, /g')"
if grep -q MISMATCH /tmp/all.txt || [ "$ok5" != match ]; then echo MISMATCH; exit 1; fi
echo done
