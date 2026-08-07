#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/founder-mode-coffee"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local text="$1"
  local expected="$2"
  [[ "$text" == *"$expected"* ]] || fail "expected output to contain: $expected"
}

output="$($CLI --help)"
assert_contains "$output" "Usage: founder-mode-coffee"
assert_contains "$output" "doctor"
assert_contains "$output" "config"
assert_contains "$output" "completion"
printf 'PASS: help exposes modern command discovery\n'

output="$($CLI --version)"
[[ "$output" == "founder-mode-coffee 2.2.0" ]] || fail "unexpected version output: $output"
printf 'PASS: version is stable and script-friendly\n'

XDG_CONFIG_HOME="$TEST_TMP/config" "$CLI" config set api "http://127.0.0.1:8787/api" >/dev/null
output="$(XDG_CONFIG_HOME="$TEST_TMP/config" "$CLI" config get api)"
[[ "$output" == "http://127.0.0.1:8787/api" ]] || fail "config round trip failed: $output"
[[ -f "$TEST_TMP/config/founder-mode-coffee/config" ]] || fail "config file was not created"
printf 'PASS: config persists under XDG_CONFIG_HOME\n'

for invocation in 'set api https://example.test/api' 'reset' 'get api'; do
  IFS=' ' read -r -a invocation_args <<< "$invocation"
  set +e
  output="$(XDG_CONFIG_HOME=/dev/null "$CLI" config "${invocation_args[@]}" 2>/dev/null)"
  exit_code=$?
  set -e
  [[ $exit_code -ne 0 ]] || fail "config $invocation succeeded with an impossible config path"
  [[ -z "$output" ]] || fail "config $invocation printed success output after a filesystem failure: $output"
done
printf 'PASS: config filesystem failures are fatal and never report success\n'

output="$(FMC_API="https://example.test/api" XDG_CONFIG_HOME="$TEST_TMP/status-config" "$CLI" status --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["command"]=="status"; assert d["version"]=="2.2.0"; assert d["api"]=="https://example.test/api"' "$output" || fail "status did not return valid JSON"
printf 'PASS: status supports automation-friendly JSON\n'

output="$(PATH="$ROOT/tests/fixtures:$PATH" FMC_API="https://api.test/v1" "$CLI" ping --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["message"]=="pong"; assert d["total_pings"]==42' "$output" || fail "ping did not preserve API JSON"
printf 'PASS: ping supports machine-readable output\n'

doctor_log="$TEST_TMP/doctor-curl.log"
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_LOG="$doctor_log" XDG_CONFIG_HOME="$TEST_TMP/doctor-config" FMC_API="https://api.test/v1" "$CLI" doctor --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["curl"] is True; assert d["api"] is True; assert d["config_writable"] is True' "$output" || fail "doctor JSON checks were not healthy"
[[ "$(<"$doctor_log")" == *"/pings/locations"* ]] || fail "doctor did not probe the read-only locations endpoint"
printf 'PASS: doctor reports setup health\n'

assert_contains "$($CLI completion bash)" "_founder_mode_coffee"
assert_contains "$($CLI completion zsh)" "#compdef founder-mode-coffee"
assert_contains "$($CLI completion fish)" "complete -c founder-mode-coffee"
printf 'PASS: completion supports bash, zsh, and fish\n'

output="$(PATH="$ROOT/tests/fixtures:$PATH" "$CLI" update --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["current"]=="2.2.0"; assert d["latest"]=="2.3.0"; assert d["update_available"] is True; assert d["url"]=="https://github.com/bossofcoffee/founder-mode-coffee-cli/releases/tag/v2.3.0"' "$output" || fail "update check JSON was incorrect"
printf 'PASS: update checks the latest GitHub release\n'

output="$(FMC_API="https://example.test/api" "$CLI" --json status)"
python3 -c 'import json,sys; assert json.loads(sys.argv[1])["command"]=="status"' "$output" || fail "global --json was not accepted before command"
printf 'PASS: global options work before subcommands\n'

colored="$(FMC_FORCE_COLOR=1 "$CLI" hello)"
[[ "$colored" == *$'\033['* ]] || fail "forced color did not emit ANSI styling"
plain="$(FMC_FORCE_COLOR=1 NO_COLOR=1 "$CLI" hello)"
[[ "$plain" != *$'\033['* ]] || fail "NO_COLOR was ignored"
plain="$(FMC_FORCE_COLOR=1 "$CLI" --no-color hello)"
[[ "$plain" != *$'\033['* ]] || fail "--no-color was ignored"
printf 'PASS: color follows terminal accessibility conventions\n'

output="$($CLI help ping)"
assert_contains "$output" "Usage: founder-mode-coffee ping"
assert_contains "$output" "--json"
output="$($CLI ping --help)"
assert_contains "$output" "Usage: founder-mode-coffee ping"
printf 'PASS: subcommands provide focused help\n'

set +e
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_FAIL=1 FMC_API="https://api.test/v1" "$CLI" ping --json 2>/dev/null)"
exit_code=$?
set -e
[[ $exit_code -eq 1 ]] || fail "failed ping returned exit code $exit_code instead of 1"
python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" || fail "failed ping did not return JSON error"

set +e
"$CLI" not-a-command >/dev/null 2>&1
exit_code=$?
set -e
[[ $exit_code -eq 2 ]] || fail "usage error returned exit code $exit_code instead of 2"
printf 'PASS: failures use predictable exit codes and JSON errors\n'

set +e
PATH="$ROOT/tests/fixtures:$PATH" "$CLI" ping --bogus >/dev/null 2>&1
exit_code=$?
set -e
[[ $exit_code -eq 2 ]] || fail "unknown command option returned exit code $exit_code instead of 2"
printf 'PASS: subcommands reject unknown options\n'

set +e
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_INVALID=1 FMC_API="https://api.test/v1" "$CLI" ping --json 2>/dev/null)"
exit_code=$?
set -e
[[ $exit_code -eq 1 ]] || fail "invalid API response returned exit code $exit_code instead of 1"
python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" || fail "invalid API response did not become JSON error"
printf 'PASS: ping rejects malformed API responses\n'

set +e
FMC_API="-K/tmp/curl-config" "$CLI" status >/dev/null 2>&1
exit_code=$?
set -e
[[ $exit_code -ne 0 ]] || fail "option-like FMC_API value was accepted"

invalid_config="$TEST_TMP/invalid-config/founder-mode-coffee"
mkdir -p "$invalid_config"
printf 'api=ftp://example.test/api\n' > "$invalid_config/config"
set +e
XDG_CONFIG_HOME="$TEST_TMP/invalid-config" "$CLI" status >/dev/null 2>&1
exit_code=$?
set -e
[[ $exit_code -ne 0 ]] || fail "invalid saved API value was accepted"

separator_log="$TEST_TMP/curl-separator.log"
PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_LOG="$separator_log" \
  FMC_API="https://api.test/v1" "$CLI" ping --json >/dev/null
assert_contains "$(<"$separator_log")" $'ARG=--\nARG=https://api.test/v1/ping'
printf 'PASS: API values are validated and curl URLs follow --\n'

glob_log="$TEST_TMP/curl-glob.log"
PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_LOG="$glob_log" \
  FMC_API='https://api.test/{one,two}' "$CLI" ping --json >/dev/null
assert_contains "$(<"$glob_log")" 'ARG=--globoff'
request_count=0
while IFS= read -r line; do
  [[ "$line" == REQUEST=* ]] && request_count=$((request_count + 1))
done < "$glob_log"
[[ $request_count -eq 1 ]] || fail "brace URL produced $request_count requests instead of one"
assert_contains "$(<"$glob_log")" 'REQUEST=https://api.test/{one,two}/ping'
printf 'PASS: curl URL globbing is disabled for literal brace paths\n'

for invalid_url in \
  'http://?' \
  'https://#fragment' \
  'http:///missing-host' \
  'https://:443/path' \
  'https://example.test/api?mode=full' \
  'https://example.test/api#section' \
  'https://.example.test/api' \
  'https://example..test/api' \
  'https://-bad.example/api' \
  'https://bad-.example/api' \
  'https://bad_label.example/api' \
  'http://256.0.0.1/api' \
  'http://127.0.0.999/api' \
  'http://example.test:0/api' \
  'http://example.test:65536/api' \
  'http://[:::]/api' \
  'http://[2001:db8::1::2]/api' \
  'http://[gggg::1]/api' \
  'http://[1:2:3:4:5:6:7]/api'; do
  set +e
  FMC_API="$invalid_url" "$CLI" status >/dev/null 2>&1
  exit_code=$?
  set -e
  [[ $exit_code -ne 0 ]] || fail "hostless API URL was accepted: $invalid_url"
done

for valid_url in \
  'https://example.test/api' \
  'http://localhost:3000' \
  'http://127.0.0.1:8787/api' \
  'https://[2001:db8::1]:443/path' \
  'http://[::1]/api' \
  'http://[1:2:3:4:5:6:7:8]:65535/api'; do
  FMC_API="$valid_url" "$CLI" status >/dev/null 2>&1 \
    || fail "valid API URL was rejected: $valid_url"
done
printf 'PASS: API URLs require a valid host and optional numeric port\n'

set +e
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_CONTROL_ERROR=1 \
  FMC_API="https://api.test/v1" "$CLI" ping --json 2>/dev/null)"
exit_code=$?
set -e
[[ $exit_code -eq 1 ]] || fail "control-character curl error returned exit code $exit_code"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["error"] == "bad\x01\t\r\x1f\x7ferror"' "$output" \
  || fail "curl control characters were not escaped as valid JSON"
printf 'PASS: JSON output escapes ASCII control characters\n'

for response in \
  '{"message":"pong"} trailing' \
  '[{"message":"pong"}]' \
  '{"message":""}' \
  '{"message":42}'; do
  set +e
  output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="$response" \
    FMC_API="https://api.test/v1" "$CLI" ping --json 2>/dev/null)"
  exit_code=$?
  set -e
  [[ $exit_code -eq 1 ]] || fail "ping accepted invalid successful response: $response"
  python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" \
    || fail "invalid successful response did not produce JSON error: $response"
done
printf 'PASS: ping validates the complete response object and message\n'

set +e
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE='{"message":"pong"}' \
  FMC_API="https://api.test/v1" "$CLI" ping 2>/dev/null)"
exit_code=$?
set -e
[[ $exit_code -eq 0 ]] || fail "message-only ping response returned exit code $exit_code"
[[ "$output" == "pong" ]] || fail "message-only ping response produced unexpected output: $output"
printf 'PASS: ping accepts an object containing only a non-empty message\n'

structured_ping='{"nested":{"timestamp":"wrong-first","total_pings":98},"message":"pong","timestamp":"top\nvalue","total_pings":7,"last":{"timestamp":"wrong-last","total_pings":99}}'
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="$structured_ping" \
  FMC_API="https://api.test/v1" "$CLI" ping)" \
  || fail "ping rejected structurally valid top-level metadata"
[[ "$output" == $'pong\nPing 7\ntop\nvalue' ]] \
  || fail "ping did not structurally extract top-level metadata: $output"
printf 'PASS: ping structurally extracts only top-level timestamp and total_pings\n'

escaped_ping='{"mess\u0061ge":"line 1\n\"quote\" \\ slash \u2615"}'
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="$escaped_ping" \
  FMC_API="https://api.test/v1" "$CLI" ping)" \
  || fail "ping did not recognize an escaped message member name"
[[ "$output" == $'line 1\n"quote" \\ slash ☕' ]] \
  || fail "ping did not semantically decode the message string: $output"
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="$escaped_ping" \
  FMC_API="https://api.test/v1" "$CLI" ping --json)" \
  || fail "escaped ping response failed in JSON mode"
[[ "$output" == "$escaped_ping" ]] || fail "ping JSON mode did not preserve the original response"
printf 'PASS: ping decodes JSON member names and message escapes\n'

raw_del_ping=$'{"message":"raw\177del"}'
output="$(LC_ALL=C PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="$raw_del_ping" \
  FMC_API="https://api.test/v1" "$CLI" ping --json)" \
  || fail "ping rejected raw U+007F in a JSON string"
[[ "$output" == "$raw_del_ping" ]] || fail "ping JSON mode did not preserve raw U+007F"

for invalid_utf8 in \
  $'{"message":"bad\200"}' \
  $'{"message":"bad\300\257"}' \
  $'{"message":"bad\355\240\200"}' \
  $'{"message":"bad\364\220\200\200"}'; do
  set +e
  output="$(LC_ALL=C PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="$invalid_utf8" \
    FMC_API="https://api.test/v1" "$CLI" ping --json 2>/dev/null)"
  exit_code=$?
  set -e
  [[ $exit_code -eq 1 ]] || fail "ping accepted invalid UTF-8 in JSON"
  python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" \
    || fail "invalid UTF-8 response did not produce valid JSON error output"
done
printf -v valid_utf8_ping '%b' '{"message":"caf\303\251 \342\202\254 \360\237\230\200"}'
output="$(LC_ALL=C PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="$valid_utf8_ping" \
  FMC_API="https://api.test/v1" "$CLI" ping --json)" \
  || fail "ping rejected well-formed raw UTF-8"
[[ "$output" == "$valid_utf8_ping" ]] || fail "ping JSON mode did not preserve valid raw UTF-8"
printf 'PASS: JSON parser accepts DEL and validates raw UTF-8 bytes under LC_ALL=C\n'

set +e
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_NUL_RESPONSE=1 \
  FMC_API="https://api.test/v1" "$CLI" ping --json 2>/dev/null)"
exit_code=$?
set -e
[[ $exit_code -eq 1 ]] || fail "ping accepted a raw NUL byte after shell transformation"
python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" \
  || fail "raw NUL response did not produce a valid JSON error"

trailing_output="$TEST_TMP/trailing-newline-message.out"
PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE='{"message":"line\n"}' \
  FMC_API="https://api.test/v1" "$CLI" ping > "$trailing_output" \
  || fail "ping rejected a valid message ending in a newline"
python3 -c 'import pathlib,sys; assert pathlib.Path(sys.argv[1]).read_bytes() == b"line\n\n"' "$trailing_output" \
  || fail "ping stripped the decoded message trailing newline"
printf 'PASS: exact response bytes and decoded trailing newlines are preserved\n'

no_curl_path="$TEST_TMP/no-curl-path"
mkdir -p "$no_curl_path"
set +e
output="$(PATH="$no_curl_path" /bin/bash "$CLI" update --json 2>/dev/null)"
exit_code=$?
set -e
[[ $exit_code -eq 1 ]] || fail "update without curl returned exit code $exit_code"
python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" \
  || fail "update without curl did not return JSON error"

set +e
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE='{}' "$CLI" update --json 2>/dev/null)"
exit_code=$?
set -e
[[ $exit_code -eq 1 ]] || fail "update without tag_name returned exit code $exit_code"
python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" \
  || fail "update without tag_name did not return JSON error"

set +e
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_NUL_UPDATE=1 "$CLI" update --json 2>/dev/null)"
exit_code=$?
set -e
[[ $exit_code -eq 1 ]] || fail "update accepted a release response containing a raw NUL"
python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" \
  || fail "raw NUL update response did not produce a valid JSON error"
printf 'PASS: update JSON mode covers dependency and response errors\n'

for response in \
  '{"tag_name":"v2.1.0"' \
  '{"release":{"tag_name":"v9.0.0"}}' \
  '{"tag_name":2.1}' \
  '{"tag_name":"v2.1"}' \
  '{"tag_name":"v2.1.0-beta"}' \
  '{"tag_name":"v2.x.0"}' \
  '{"tag_name":"v02.1.0"}' \
  '{"tag_name":"2.01.0"}' \
  '{"tag_name":"2.1.00"}' \
  '{"tag_name":"2.1.0"} trailing'; do
  update_error="$TEST_TMP/update-error"
  set +e
  output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="$response" \
    "$CLI" update --json 2>"$update_error")"
  exit_code=$?
  set -e
  [[ $exit_code -eq 1 ]] || fail "update accepted malformed JSON or invalid tag: $response"
  python3 -c 'import json,sys; assert "error" in json.loads(sys.argv[1])' "$output" \
    || fail "invalid update response did not produce a JSON error: $response"
  case "$(<"$update_error")" in
    *arithmetic*|*"value too great"*|*"syntax error"*)
      fail "invalid release tag produced an arithmetic diagnostic: $response"
      ;;
  esac
done

output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE='{"tag_name":"2.2.1"}' \
  "$CLI" update --json)" || fail "update rejected a valid release tag without v"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["latest"]=="2.2.1" and d["update_available"] is True' "$output" \
  || fail "update mishandled a valid release tag without v"
huge_version='v2.999999999999999999999999999999999999999999999999.0'
output="$(PATH="$ROOT/tests/fixtures:$PATH" MOCK_CURL_RESPONSE="{\"tag_name\":\"$huge_version\"}" \
  "$CLI" update --json 2>"$TEST_TMP/huge-version-error")" \
  || fail "update rejected an arbitrarily large semantic version component: $(<"$TEST_TMP/huge-version-error")"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["update_available"] is True' "$output" \
  || fail "update did not compare an arbitrarily large semantic version component"
printf 'PASS: update validates complete JSON and strict semantic release tags\n'

for command in hello ping status doctor config completion update help; do
  output="$($CLI "$command" --help)" || fail "$command --help failed"
  assert_contains "$output" "Usage: founder-mode-coffee"
done

for invocation in \
  'config path extra' \
  'config get api extra' \
  'config reset extra' \
  'completion bash extra' \
  'help ping extra'; do
  IFS=' ' read -r -a invocation_args <<< "$invocation"
  set +e
  "$CLI" "${invocation_args[@]}" >/dev/null 2>&1
  exit_code=$?
  set -e
  [[ $exit_code -eq 2 ]] || fail "$invocation returned $exit_code instead of rejecting surplus arguments"
done
printf 'PASS: command help and surplus argument handling are consistent\n'

productivity_data="$TEST_TMP/productivity-data"
output="$(XDG_DATA_HOME="$productivity_data" "$CLI" capture "Ship the onboarding draft")"
[[ "$output" == "Captured #1: Ship the onboarding draft" ]] \
  || fail "capture returned unexpected output: $output"
output="$(XDG_DATA_HOME="$productivity_data" "$CLI" today)"
assert_contains "$output" "FOCUS  Not set"
assert_contains "$output" "[1] Ship the onboarding draft"
printf 'PASS: capture feeds the local daily brief\n'

output="$(XDG_DATA_HOME="$productivity_data" "$CLI" focus set "Publish the launch page")"
[[ "$output" == "Focus set: Publish the launch page" ]] || fail "focus set returned unexpected output: $output"
output="$(XDG_DATA_HOME="$productivity_data" "$CLI" focus show)"
[[ "$output" == "Publish the launch page" ]] || fail "focus show returned unexpected output: $output"
output="$(XDG_DATA_HOME="$productivity_data" "$CLI" today)"
assert_contains "$output" "FOCUS  Publish the launch page"
printf 'PASS: focus sets the outcome shown in the daily brief\n'

XDG_DATA_HOME="$productivity_data" "$CLI" capture "Send the supplier note" >/dev/null
output="$(XDG_DATA_HOME="$productivity_data" "$CLI" "done" 1)"
[[ "$output" == "Completed #1: Ship the onboarding draft" ]] || fail "done returned unexpected output: $output"
output="$(XDG_DATA_HOME="$productivity_data" "$CLI" today)"
[[ "$output" != *"Ship the onboarding draft"* ]] || fail "completed item remained in the daily brief"
assert_contains "$output" "[2] Send the supplier note"
[[ -f "$productivity_data/founder-mode-coffee/completed/00000001" ]] || fail "completed item was not archived"
printf 'PASS: done removes an item from the active brief and archives it\n'

output="$(XDG_DATA_HOME="$productivity_data" "$CLI" prompt "What should I do next?")"
assert_contains "$output" "Act as a practical operating partner for a founder."
assert_contains "$output" "Current focus:"
assert_contains "$output" "Publish the launch page"
assert_contains "$output" "[2] Send the supplier note"
assert_contains "$output" "Request:"
assert_contains "$output" "What should I do next?"
[[ "$output" != *"Ship the onboarding draft"* ]] || fail "prompt included a completed item"
printf 'PASS: prompt turns local founder context into an AI-ready request\n'

ai_runner="$TEST_TMP/fake-ai-runner"
ai_log="$TEST_TMP/fake-ai-prompt"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'command cat > "$MOCK_AI_LOG"' 'printf "Start with item 2.\\n"' > "$ai_runner"
chmod +x "$ai_runner"
output="$(XDG_DATA_HOME="$productivity_data" FMC_AI_RUNNER="$ai_runner" MOCK_AI_LOG="$ai_log" \
  "$CLI" ask "What should I do next?")"
[[ "$output" == "Start with item 2." ]] || fail "ask did not preserve runner output: $output"
assert_contains "$(<"$ai_log")" "Publish the launch page"
assert_contains "$(<"$ai_log")" "What should I do next?"
printf 'PASS: ask runs a provider-neutral AI executable with founder context on stdin\n'

mkdir -p "$TEST_TMP/ai-bin"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'for arg in "$@"; do printf "ARG=%s\\n" "$arg" >> "$MOCK_AI_ARGS"; done' 'printf "Hermes response.\\n"' > "$TEST_TMP/ai-bin/hermes"
chmod +x "$TEST_TMP/ai-bin/hermes"
hermes_args="$TEST_TMP/hermes-args"
output="$(PATH="$TEST_TMP/ai-bin:$PATH" XDG_DATA_HOME="$productivity_data" FMC_AI_RUNNER=hermes \
  MOCK_AI_ARGS="$hermes_args" "$CLI" ask "Choose the next move")"
[[ "$output" == "Hermes response." ]] || fail "Hermes adapter returned unexpected output: $output"
assert_contains "$(<"$hermes_args")" $'ARG=chat\nARG=-q'
assert_contains "$(<"$hermes_args")" "Publish the launch page"
printf 'PASS: ask adapts founder context to Hermes non-interactive chat\n'

output="$(XDG_DATA_HOME="$productivity_data" "$CLI" --json today)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["focus"]=="Publish the launch page"; assert d["open"]==[{"id":2,"text":"Send the supplier note"}]' "$output" \
  || fail "global today JSON did not expose the current founder context"
output="$(XDG_DATA_HOME="$productivity_data" "$CLI" today --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["open"][0]["id"]==2' "$output" \
  || fail "command-local today --json did not return structured context"
printf 'PASS: today provides structured context for scripts and agents\n'

help_output="$($CLI --help)"
for command in capture today "done" focus prompt ask; do
  assert_contains "$help_output" "$command"
  output="$($CLI "$command" --help)" || fail "$command --help failed"
  assert_contains "$output" "Usage: founder-mode-coffee $command"
done
for shell in bash zsh fish; do
  completion_output="$($CLI completion "$shell")"
  for command in capture today "done" focus prompt ask; do
    assert_contains "$completion_output" "$command"
  done
done
printf 'PASS: productivity and AI commands are discoverable\n'

output="$(XDG_DATA_HOME="$productivity_data" "$CLI" focus clear)"
[[ "$output" == "Focus cleared." ]] || fail "focus clear returned unexpected output: $output"
[[ "$(XDG_DATA_HOME="$productivity_data" "$CLI" focus show)" == "Not set" ]] || fail "focus remained set after clear"
printf 'PASS: focus can be cleared without resetting captured work\n'

concurrent_data="$TEST_TMP/concurrent-data"
pids=()
for i in {1..12}; do
  XDG_DATA_HOME="$concurrent_data" "$CLI" capture "Concurrent item $i" > "$TEST_TMP/concurrent-$i.out" &
  pids+=("$!")
done
capture_failed=false
for pid in "${pids[@]}"; do
  wait "$pid" || capture_failed=true
done
[[ "$capture_failed" == false ]] || fail "a concurrent capture command failed"
output="$(XDG_DATA_HOME="$concurrent_data" "$CLI" today --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert len(d["open"])==12; assert sorted(x["id"] for x in d["open"])==list(range(1,13))' "$output" \
  || fail "concurrent captures reused or lost item IDs"
printf 'PASS: concurrent captures retain unique ordered IDs\n'

default_output="$(XDG_DATA_HOME="$productivity_data" "$CLI")"
assert_contains "$default_output" "FOCUS"
assert_contains "$default_output" "[2] Send the supplier note"
[[ "$default_output" != *"The first roast is in development"* ]] || fail "default command still opened the welcome screen"
printf 'PASS: the default command opens the daily operating brief\n'

conflict_data="$TEST_TMP/conflict-data/founder-mode-coffee"
mkdir -p "$conflict_data/inbox" "$conflict_data/completed"
printf 'new open record\n' > "$conflict_data/inbox/00000001"
printf 'original archived record\n' > "$conflict_data/completed/00000001"
set +e
XDG_DATA_HOME="$TEST_TMP/conflict-data" "$CLI" "done" 1 > /dev/null 2> "$TEST_TMP/conflict-error"
exit_code=$?
set -e
[[ $exit_code -eq 1 ]] || fail "done overwrote a conflicting archived item"
[[ "$(<"$conflict_data/completed/00000001")" == "original archived record" ]] || fail "archived item content was replaced"
[[ -f "$conflict_data/inbox/00000001" ]] || fail "open item disappeared after archive conflict"
printf 'PASS: done never overwrites an archived item\n'

interactive_data="$TEST_TMP/interactive-data"
output="$(printf '%s\n' '/capture Draft the roast update' '/focus Ship the founder brief' '/today' '/quit' | \
  XDG_DATA_HOME="$interactive_data" "$CLI" interactive)"
assert_contains "$output" "F M C"
assert_contains "$output" "Founder Mode Coffee"
assert_contains "$output" "Captured #1: Draft the roast update"
assert_contains "$output" "Focus set: Ship the founder brief"
assert_contains "$output" "[1] Draft the roast update"
assert_contains "$output" "Session closed."
printf 'PASS: interactive harness routes slash commands through founder context\n'

help_output="$($CLI --help)"
assert_contains "$help_output" "interactive"
output="$($CLI interactive --help)"
assert_contains "$output" "Usage: founder-mode-coffee interactive"
for shell in bash zsh fish; do
  assert_contains "$($CLI completion "$shell")" "interactive"
done
printf 'PASS: interactive harness is discoverable\n'

output="$(printf '/quit\n' | FMC_FORCE_INTERACTIVE=1 XDG_DATA_HOME="$TEST_TMP/forced-interactive" "$CLI")"
assert_contains "$output" "F M C"
assert_contains "$output" "Session closed."
printf 'PASS: terminal launches can default to the interactive harness\n'

output="$(FMC_FORCE_INTERACTIVE=1 XDG_DATA_HOME="$TEST_TMP/json-default" "$CLI" --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert "focus" in d and "open" in d' "$output" \
  || fail "global --json without a command opened the interactive harness"
printf 'PASS: global JSON mode overrides automatic interactive startup\n'

partial_data="$TEST_TMP/partial-input"
output="$(printf '%s' '/capture Keep the final line' | XDG_DATA_HOME="$partial_data" "$CLI" interactive)"
assert_contains "$output" "Captured #1: Keep the final line"
assert_contains "$output" "Session closed."
printf 'PASS: interactive harness processes a final unterminated line before EOF\n'

quiet_runner="$TEST_TMP/quiet-runner"
quiet_log="$TEST_TMP/quiet-runner.log"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf called >> "$QUIET_LOG"' > "$quiet_runner"
chmod +x "$quiet_runner"
output="$(printf '%s\n' '   ' '/ask    ' '/quit' | QUIET_LOG="$quiet_log" FMC_AI_RUNNER="$quiet_runner" \
  XDG_DATA_HOME="$TEST_TMP/quiet-input" "$CLI" interactive)"
[[ ! -e "$quiet_log" ]] || fail "whitespace-only input invoked the AI runner"
assert_contains "$output" "Session closed."
printf 'PASS: whitespace-only interactive input never invokes AI\n'
