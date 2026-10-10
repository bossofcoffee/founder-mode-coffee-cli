#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/founder-mode-coffee"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
[[ "$(XDG_CONFIG_HOME="$TEST_TMP/config" "$CLI" config get api)" == 'https://www.foundermodecoffee.com/api' ]]
printf 'PASS: canonical API default avoids cross-host bearer redirects\n'
result="$("$CLI" net --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert "interface" in d and "gateway" in d and "local_address" in d' "$result"
printf 'PASS: local network diagnostics JSON\n'
output="$(printf '/help\n/quit\n' | "$CLI" interactive)"
[[ "$output" == *'F O U N D E R'* && "$output" == *'/network'* && "$output" == *'/checkin'* && "$output" == *'/net'* ]]
printf 'PASS: branded startup and discoverable commands\n'
