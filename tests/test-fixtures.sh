#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
SCRIPT="$PROJECT_DIR/bin/unity-licensing-mode"
ORIGINAL_PATH="$PATH"
REAL_JQ="$(command -v jq 2>/dev/null || true)"
TEST_ROOT="$(mktemp -d /tmp/unity-licensing-mode-fixtures.XXXXXX)"
FAKE_BIN="$TEST_ROOT/bin"
CONFIG_FILE="$TEST_ROOT/config.conf"
STATE_DIR="$TEST_ROOT/state"
USER_CONFIG_DIR="$TEST_ROOT/user-config"
SYSTEM_CONFIG_DIR="$TEST_ROOT/system-config"
LICENSE_DIR="$TEST_ROOT/licenses"
SERVER_URL="http://license.example.test:1554"
NETWORK_ID="private-network-id-for-fixtures"
NETWORK_NAME="private-network-name-for-fixtures"
CLI_FILE="$TEST_ROOT/fake-license-cli"
CLI_ARGS_LOG="$TEST_ROOT/cli-args"
CLI_TOKEN_LOG="$TEST_ROOT/cli-token"
JQ_CALL_LOG="$TEST_ROOT/jq-calls"
FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST=0
CLI_MODE_OVERRIDE=""

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'fixture failure: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

assert_file_equals() {
  local path="$1"
  local expected="$2"
  [[ -f "$path" ]] || fail "expected file to exist: $path"
  [[ "$(<"$path")" == "$expected" ]] || fail "unexpected contents in $path"
}

write_fake_jq() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -e' > "$FAKE_BIN/jq"
  if [[ -n "$REAL_JQ" ]]; then
    printf '%s\n' \
      'call_count=0' \
      'if [[ -f "$FAKE_JQ_CALL_LOG" ]]; then call_count="$(<"$FAKE_JQ_CALL_LOG")"; fi' \
      'call_count=$((call_count + 1))' \
      'printf "%s" "$call_count" > "$FAKE_JQ_CALL_LOG"' \
      'target="$6"' \
      'if [[ "$FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST" == "1" && "$call_count" -gt 1 && "$(basename "$target")" == "services-config.json" ]]; then exit 1; fi' \
      'exec "$FAKE_JQ_REAL" "$@"' >> "$FAKE_BIN/jq"
  else
    printf '%s\n' \
      'call_count=0' \
      'if [[ -f "$FAKE_JQ_CALL_LOG" ]]; then call_count="$(<"$FAKE_JQ_CALL_LOG")"; fi' \
      'call_count=$((call_count + 1))' \
      'printf "%s" "$call_count" > "$FAKE_JQ_CALL_LOG"' \
      'expected=""' \
      'target=""' \
      'while [[ "$#" -gt 0 ]]; do' \
      '  case "$1" in' \
      '    --arg) expected="$3"; shift 3 ;;' \
      '    -e) shift ;;' \
      '    *) target="$1"; shift; target="$1"; shift ;;' \
      '  esac' \
      'done' \
      'if [[ "$FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST" == "1" && "$call_count" -gt 1 && "$(basename "$target")" == "services-config.json" ]]; then exit 1; fi' \
      'grep -q "{" "$target"' \
      'grep -Fq "\"licensingServiceBaseUrl\":\"$expected\"" "$target"' >> "$FAKE_BIN/jq"
  fi
  chmod +x "$FAKE_BIN/jq"
}

write_fake_curl() {
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BIN/curl"
  chmod +x "$FAKE_BIN/curl"
}

write_fake_pgrep() {
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$FAKE_BIN/pgrep"
  chmod +x "$FAKE_BIN/pgrep"
}

write_fake_gnu_stat() {
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$1" == "-f" ]]; then' \
    '  printf "  File: fake-config\\n    Type: fake-filesystem\\n"' \
    '  exit 1' \
    'fi' \
    'if [[ "$1" == "-c" ]]; then' \
    '  printf "600\\n"' \
    '  exit 0' \
    'fi' \
    'exit 1' > "$FAKE_BIN/stat"
  chmod +x "$FAKE_BIN/stat"
}

write_fake_cli() {
  printf '%s\n' '#!/usr/bin/env bash' 'set -e' > "$CLI_FILE"
  printf '%s\n' \
    'printf "%s" "$*" > "$CLI_ARGS_LOG"' \
    'token=""' \
    'if [[ "$#" -eq 1 ]]; then IFS= read -r token || true; fi' \
    'printf "%s" "$token" > "$CLI_TOKEN_LOG"' >> "$CLI_FILE"
  chmod +x "$CLI_FILE"
}

write_config() {
  local provider="${1:-direct}"
  local cli_mode="${2-stdin}"

  printf '%s\n' \
    "UNITY_NETWORK_PROVIDER=\"$provider\"" \
    "UNITY_NETWORK_ID=\"$NETWORK_ID\"" \
    "UNITY_NETWORK_NAME=\"$NETWORK_NAME\"" \
    'UNITY_NETWORK_ALLOW_CHANGES="false"' \
    "UNITY_LICENSE_SERVER_URL=\"$SERVER_URL\"" \
    "UNITY_LICENSE_CLI=\"$CLI_FILE\"" > "$CONFIG_FILE"
  if [[ -n "$cli_mode" ]]; then
    printf 'UNITY_LICENSE_CLI_MODE="%s"\n' "$cli_mode" >> "$CONFIG_FILE"
  fi
  chmod 600 "$CONFIG_FILE"
}

valid_config() {
  printf '{"licensingServiceBaseUrl":"%s"}\n' "$SERVER_URL"
}

run_tool() {
  env \
    UNITY_LICENSING_MODE_PLATFORM=Darwin \
    UNITY_LICENSING_MODE_CONFIG_FILE="$CONFIG_FILE" \
    UNITY_LICENSING_MODE_STATE_DIR="$STATE_DIR" \
    UNITY_LICENSING_MODE_USER_CONFIG_DIR="$USER_CONFIG_DIR" \
    UNITY_LICENSING_MODE_SYSTEM_CONFIG_DIR="$SYSTEM_CONFIG_DIR" \
    UNITY_LICENSING_MODE_LICENSE_DIR="$LICENSE_DIR" \
    UNITY_LICENSING_MODE_SKIP_PROCESS_ACTIONS=1 \
    FAKE_JQ_CALL_LOG="$JQ_CALL_LOG" \
    FAKE_JQ_REAL="$REAL_JQ" \
    FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST="$FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST" \
    CLI_ARGS_LOG="$CLI_ARGS_LOG" \
    CLI_TOKEN_LOG="$CLI_TOKEN_LOG" \
    UNITY_LICENSE_CLI_MODE="$CLI_MODE_OVERRIDE" \
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    "$SCRIPT" "$@"
}

mkdir -p "$FAKE_BIN" "$USER_CONFIG_DIR" "$SYSTEM_CONFIG_DIR" "$LICENSE_DIR"
write_fake_jq
write_fake_curl
write_fake_pgrep
write_fake_cli
write_config

# The read-only JSON report must not echo either configured private value.
status_json="$(run_tool --json status)"
assert_contains "$status_json" '"network_provider": "direct"'
assert_not_contains "$status_json" "$SERVER_URL"
assert_not_contains "$status_json" "$NETWORK_ID"
assert_not_contains "$status_json" "$NETWORK_NAME"
if [[ -n "$REAL_JQ" ]]; then
  printf '%s\n' "$status_json" | "$REAL_JQ" -e . >/dev/null
fi

# GNU stat may emit non-mode filesystem output before failing the BSD syntax.
write_fake_gnu_stat
gnu_stat_json="$(run_tool --json status)"
assert_contains "$gnu_stat_json" '"configuration_permissions": "secure"'
assert_contains "$gnu_stat_json" '"network_provider": "direct"'
rm -f "$FAKE_BIN/stat"

# Lease filenames are also redacted from the human-readable status report.
touch "$LICENSE_DIR/sensitive-lease-token.xml"
status_text="$(run_tool status)"
assert_contains "$status_text" 'Floating lease files: 1'
assert_not_contains "$status_text" 'sensitive-lease-token'
rm -f "$LICENSE_DIR/sensitive-lease-token.xml"

# Doctor is read-only, reports the bounded fake reachability probe, and stays redacted.
doctor_json="$(run_tool --json doctor)"
assert_contains "$doctor_json" '"server_reachability": "reachable"'
assert_not_contains "$doctor_json" "$SERVER_URL"
assert_not_contains "$doctor_json" "$NETWORK_ID"
assert_not_contains "$doctor_json" "$NETWORK_NAME"
if [[ -n "$REAL_JQ" ]]; then
  printf '%s\n' "$doctor_json" | "$REAL_JQ" -e . >/dev/null
fi

# Insecure configuration permissions are reported and block mode changes.
chmod 644 "$CONFIG_FILE"
insecure_json="$(run_tool --json status)"
assert_contains "$insecure_json" '"configuration": "insecure"'
if run_tool --dry-run floating >/dev/null 2>&1; then
  fail 'insecure configuration unexpectedly allowed a mode change'
fi
chmod 600 "$CONFIG_FILE"

# A held lock blocks even a dry-run without changing the lock directory.
mkdir -p "$STATE_DIR"
mkdir "$STATE_DIR/.lock"
if run_tool --dry-run personal >/dev/null 2>&1; then
  fail 'held lock unexpectedly allowed an operation'
fi
lock_doctor_json="$(run_tool --json doctor)"
assert_contains "$lock_doctor_json" '"transaction_lock": "held"'
assert_contains "$lock_doctor_json" '"ok": false'
rmdir "$STATE_DIR/.lock"

# Invalid provider settings are reported by doctor instead of terminating it.
write_config invalid stdin
invalid_doctor_json="$(run_tool --json doctor)"
assert_contains "$invalid_doctor_json" '"network_provider": "invalid"'
assert_contains "$invalid_doctor_json" '"ok": false'
write_config

# A dry-run validates the eligible candidate but does not create state or config files.
printf '%s\n' '{"licensingServiceBaseUrl":"http://wrong.example.test:1554"}' > "$USER_CONFIG_DIR/services-config.json"
valid_config > "$SYSTEM_CONFIG_DIR/services-config.json.legacy.bak"
dry_output="$(run_tool --dry-run floating)"
assert_contains "$dry_output" 'Dry run enabled'
assert_contains "$dry_output" 'Would preserve a validated floating template'
[[ ! -f "$STATE_DIR/services-config.floating.template.json" ]] || fail 'dry-run created a template'
[[ ! -f "$SYSTEM_CONFIG_DIR/services-config.json" ]] || fail 'dry-run installed a system config'

# The wrong-endpoint active config is ignored; the valid backup is selected and installed.
floating_output="$(run_tool floating)"
assert_contains "$floating_output" 'Floating licensing mode is active.'
assert_file_equals "$SYSTEM_CONFIG_DIR/services-config.json" "$(valid_config | tr -d '\n')"
[[ ! -f "$USER_CONFIG_DIR/services-config.json" ]] || fail 'user config remained active'
assert_file_equals "$STATE_DIR/services-config.user.disabled.json" '{"licensingServiceBaseUrl":"http://wrong.example.test:1554"}'
assert_file_equals "$STATE_DIR/services-config.floating.template.json" "$(valid_config | tr -d '\n')"
find "$STATE_DIR/transactions" -name metadata -type f -print -exec grep -q '^status=committed$' {} \; >/dev/null || fail 'missing committed transaction metadata'

# Personal mode replaces a stale optional template instead of refusing to disable floating mode.
rm -rf "$STATE_DIR" "$SYSTEM_CONFIG_DIR" "$USER_CONFIG_DIR"
mkdir -p "$STATE_DIR" "$USER_CONFIG_DIR" "$SYSTEM_CONFIG_DIR"
printf '%s\n' '{"licensingServiceBaseUrl":"http://stale.example.test:1554"}' > "$STATE_DIR/services-config.floating.template.json"
valid_config > "$SYSTEM_CONFIG_DIR/services-config.json"
personal_output="$(run_tool personal 2>&1)"
assert_contains "$personal_output" 'Personal mode is active.'
[[ ! -f "$SYSTEM_CONFIG_DIR/services-config.json" ]] || fail 'personal mode left the system config active'
assert_file_equals "$STATE_DIR/services-config.system.disabled.json" "$(valid_config | tr -d '\n')"
assert_file_equals "$STATE_DIR/services-config.floating.template.json" "$(valid_config | tr -d '\n')"

# A failed post-install validation restores the original active user config and removes new state.
rm -rf "$STATE_DIR" "$SYSTEM_CONFIG_DIR" "$USER_CONFIG_DIR"
mkdir -p "$USER_CONFIG_DIR" "$SYSTEM_CONFIG_DIR"
valid_config > "$USER_CONFIG_DIR/services-config.json"
: > "$JQ_CALL_LOG"
rollback_status=0
if FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST=1 run_tool floating > "$TEST_ROOT/rollback-output" 2>&1; then
  rollback_status=0
else
  rollback_status=$?
fi
[[ "$rollback_status" -ne 0 ]] || fail 'rollback fixture unexpectedly succeeded'
assert_file_equals "$USER_CONFIG_DIR/services-config.json" "$(valid_config | tr -d '\n')"
[[ ! -f "$SYSTEM_CONFIG_DIR/services-config.json" ]] || fail 'rollback left a new system config active'
[[ ! -f "$STATE_DIR/services-config.floating.template.json" ]] || fail 'rollback left a new template'
rollback_output="$(<"$TEST_ROOT/rollback-output")"
assert_contains "$rollback_output" 'original Unity configuration was restored'
find "$STATE_DIR/transactions" -name metadata -type f -print -exec grep -q '^status=rolled_back$' {} \; >/dev/null || fail 'missing rolled-back transaction metadata'

# Commands that do not edit configuration use a lock but create no transaction snapshots.
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
run_tool reload-client >/dev/null
[[ ! -d "$STATE_DIR/transactions" ]] || fail 'reload-client created an unnecessary configuration transaction'

# Stdin token input reaches the CLI through stdin, while the process arguments stay token-free.
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
: > "$CLI_ARGS_LOG"
: > "$CLI_TOKEN_LOG"
token_status=0
if printf '%s\n' 'sensitive-floating-token' | run_tool return-floating > "$TEST_ROOT/token-output" 2>&1; then
  token_status=0
else
  token_status=$?
fi
[[ "$token_status" -eq 0 ]] || fail "return-floating fixture failed with status $token_status: $(<"$TEST_ROOT/token-output")"
assert_file_equals "$CLI_ARGS_LOG" '--return-floating'
assert_file_equals "$CLI_TOKEN_LOG" 'sensitive-floating-token'

# The environment override wins over the configured CLI mode.
CLI_MODE_OVERRIDE="argument"
: > "$CLI_ARGS_LOG"
: > "$CLI_TOKEN_LOG"
printf '%s\n' 'environment-override-token' | run_tool return-floating >/dev/null 2>&1
assert_file_equals "$CLI_ARGS_LOG" '--return-floating environment-override-token'
assert_file_equals "$CLI_TOKEN_LOG" ''
[[ ! -d "$STATE_DIR/transactions" ]] || fail 'return-floating created an unnecessary configuration transaction'
CLI_MODE_OVERRIDE=""

# The deprecated positional token is forwarded to an argument-mode CLI.
write_config direct argument
: > "$CLI_ARGS_LOG"
: > "$CLI_TOKEN_LOG"
run_tool return-floating 'compatibility-token' >/dev/null 2>&1
assert_file_equals "$CLI_ARGS_LOG" '--return-floating compatibility-token'
assert_file_equals "$CLI_TOKEN_LOG" ''

# Without an explicit mode, the Unity Licensing Client-compatible argument mode is used.
write_config direct ''
: > "$CLI_ARGS_LOG"
: > "$CLI_TOKEN_LOG"
printf '%s\n' 'default-mode-token' | run_tool return-floating >/dev/null 2>&1
assert_file_equals "$CLI_ARGS_LOG" '--return-floating default-mode-token'
assert_file_equals "$CLI_TOKEN_LOG" ''

# Dry-run return does not prompt for or invoke the configured CLI.
rm -f "$CLI_ARGS_LOG" "$CLI_TOKEN_LOG"
printf '' | run_tool --dry-run return-floating > "$TEST_ROOT/dry-return-output"
[[ ! -e "$CLI_ARGS_LOG" && ! -e "$CLI_TOKEN_LOG" ]] || fail 'dry-run invoked the return CLI'
assert_contains "$(<"$TEST_ROOT/dry-return-output")" 'Dry run: would return a floating lease'

printf 'fixture checks passed\n'
