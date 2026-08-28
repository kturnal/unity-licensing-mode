#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail
#
# Fixture coverage for the ZeroTier "floating" path: joining the configured
# network, reading its authorization status, and reporting network changes that
# an automatic rollback cannot undo. Everything ZeroTier-related is faked, so
# this runs without zerotier-cli, sudo, or a real network.

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
SCRIPT="$PROJECT_DIR/bin/unity-licensing-mode"
ORIGINAL_PATH="$PATH"
REAL_JQ="$(command -v jq 2>/dev/null || true)"
TEST_ROOT="$(mktemp -d /tmp/unity-licensing-mode-zerotier.XXXXXX)"
FAKE_BIN="$TEST_ROOT/bin"
CONFIG_FILE="$TEST_ROOT/config.conf"
STATE_DIR="$TEST_ROOT/state"
USER_CONFIG_DIR="$TEST_ROOT/user-config"
SYSTEM_CONFIG_DIR="$TEST_ROOT/system-config"
LICENSE_DIR="$TEST_ROOT/licenses"
ZT_STATE_DIR="$TEST_ROOT/zt-state"
ZT_LOG="$TEST_ROOT/zt-calls"
JQ_CALL_LOG="$TEST_ROOT/jq-calls"
SERVER_URL="http://license.example.test:1554"
NWID="0123456789abcdef"
NODE_ID="1a2b3c4d5e"
# A deliberately multi-word name: the previous "listnetworks" column parser read
# the status from a fixed field, so any name with spaces shifted the columns.
NETWORK_NAME="Example ZeroTier Network"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'zerotier fixture failure: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"$'\n'"---"$'\n'"$1"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "expected output NOT to contain: $2"$'\n'"---"$'\n'"$1"
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

# "sudo" in this suite is only ever used for "sudo zerotier-cli join"; run the
# wrapped command directly.
write_fake_sudo() {
  printf '%s\n' '#!/usr/bin/env bash' 'exec "$@"' > "$FAKE_BIN/sudo"
  chmod +x "$FAKE_BIN/sudo"
}

# Fake zerotier-cli driven entirely by FZT_* environment variables. Membership
# and the allowManaged flag are persisted as marker files so state set by one
# invocation (join / set) is visible to the next (listnetworks / get) within a
# single tool run.
write_fake_zerotier_cli() {
  cat > "$FAKE_BIN/zerotier-cli" <<'EOF'
#!/usr/bin/env bash
set -e

printf '%s\n' "$*" >> "$FZT_LOG"

state_dir="$FZT_STATE_DIR"
mkdir -p "$state_dir"
joined_marker="$state_dir/joined"
managed_marker="$state_dir/allowManaged"
if [[ ! -e "$state_dir/.init" ]]; then
  [[ "${FZT_INITIAL_JOINED:-0}" == "1" ]] && : > "$joined_marker"
  printf '%s' "${FZT_INITIAL_ALLOW_MANAGED:-0}" > "$managed_marker"
  : > "$state_dir/.init"
fi

cmd="${1:-}"
shift || true

case "$cmd" in
  info)
    printf '200 info %s 1.99.0 ONLINE\n' "${FZT_NODE_ID:-0000000000}"
    ;;
  listnetworks)
    printf '200 listnetworks <nwid> <name> <mac> <status> <type> <dev> <ZT assigned ips>\n'
    if [[ -e "$joined_marker" && "${FZT_NEVER_REGISTERS:-0}" != "1" ]]; then
      printf '200 listnetworks %s %s de:ad:be:ef:00:01 %s PRIVATE zt0 -\n' \
        "$FZT_NWID" "${FZT_NAME:-fake-net}" "${FZT_STATUS:-OK}"
    fi
    ;;
  join)
    if [[ "${FZT_JOIN_FAILS:-0}" == "1" ]]; then
      printf 'join failed\n' >&2
      exit 1
    fi
    : > "$joined_marker"
    printf '200 join OK\n'
    ;;
  leave)
    rm -f "$joined_marker"
    printf '200 leave OK\n'
    ;;
  get)
    case "${2:-}" in
      status)       printf '%s\n' "${FZT_STATUS:-OK}" ;;
      allowManaged) printf '%s\n' "$(<"$managed_marker")" ;;
      *)            printf '\n' ;;
    esac
    ;;
  set)
    for arg in "$@"; do
      case "$arg" in
        allowManaged=*) printf '%s' "${arg#allowManaged=}" > "$managed_marker" ;;
      esac
    done
    printf '200 set OK\n'
    ;;
  *)
    printf 'fake zerotier-cli: unhandled command: %s %s\n' "$cmd" "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/zerotier-cli"
}

write_config() {
  printf '%s\n' \
    'UNITY_NETWORK_PROVIDER="zerotier"' \
    "UNITY_NETWORK_ID=\"$NWID\"" \
    "UNITY_NETWORK_NAME=\"$NETWORK_NAME\"" \
    'UNITY_NETWORK_ALLOW_CHANGES="false"' \
    "UNITY_LICENSE_SERVER_URL=\"$SERVER_URL\"" \
    'UNITY_LICENSE_CLI_MODE="stdin"' > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

valid_config() {
  printf '{"licensingServiceBaseUrl":"%s"}\n' "$SERVER_URL"
}

# reset_state
# Restore a clean pre-"floating" world: a valid active user config the tool can
# preserve as the floating template, empty logs, and no lingering per-case knobs
# (bash keeps `VAR=val func` assignments set after the call returns).
reset_state() {
  rm -rf "$STATE_DIR" "$USER_CONFIG_DIR" "$SYSTEM_CONFIG_DIR" "$ZT_STATE_DIR"
  mkdir -p "$USER_CONFIG_DIR" "$SYSTEM_CONFIG_DIR"
  valid_config > "$USER_CONFIG_DIR/services-config.json"
  : > "$JQ_CALL_LOG"
  : > "$ZT_LOG"
  unset FZT_STATUS FZT_INITIAL_JOINED FZT_INITIAL_ALLOW_MANAGED FZT_JOIN_FAILS \
    FZT_NEVER_REGISTERS FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST ALLOW_CHANGES ZT_JOIN_TIMEOUT
}

# run_floating <allow_changes> [extra env assignments...] -- [script args...]
run_tool() {
  env \
    UNITY_LICENSING_MODE_PLATFORM=Darwin \
    UNITY_LICENSING_MODE_CONFIG_FILE="$CONFIG_FILE" \
    UNITY_LICENSING_MODE_STATE_DIR="$STATE_DIR" \
    UNITY_LICENSING_MODE_USER_CONFIG_DIR="$USER_CONFIG_DIR" \
    UNITY_LICENSING_MODE_SYSTEM_CONFIG_DIR="$SYSTEM_CONFIG_DIR" \
    UNITY_LICENSING_MODE_LICENSE_DIR="$LICENSE_DIR" \
    UNITY_LICENSING_MODE_SKIP_PROCESS_ACTIONS=1 \
    UNITY_LICENSING_MODE_ZT_JOIN_TIMEOUT="${ZT_JOIN_TIMEOUT:-2}" \
    UNITY_LICENSING_MODE_NO_COLOR=1 \
    UNITY_NETWORK_ALLOW_CHANGES="${ALLOW_CHANGES:-true}" \
    FAKE_JQ_CALL_LOG="$JQ_CALL_LOG" \
    FAKE_JQ_REAL="$REAL_JQ" \
    FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST="${FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST:-0}" \
    FZT_LOG="$ZT_LOG" \
    FZT_STATE_DIR="$ZT_STATE_DIR" \
    FZT_NWID="$NWID" \
    FZT_NODE_ID="$NODE_ID" \
    FZT_NAME="$NETWORK_NAME" \
    FZT_STATUS="${FZT_STATUS:-OK}" \
    FZT_INITIAL_JOINED="${FZT_INITIAL_JOINED:-0}" \
    FZT_INITIAL_ALLOW_MANAGED="${FZT_INITIAL_ALLOW_MANAGED:-1}" \
    FZT_JOIN_FAILS="${FZT_JOIN_FAILS:-0}" \
    FZT_NEVER_REGISTERS="${FZT_NEVER_REGISTERS:-0}" \
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    "$SCRIPT" "$@"
}

mkdir -p "$FAKE_BIN" "$LICENSE_DIR"
write_fake_jq
write_fake_curl
write_fake_pgrep
write_fake_sudo
write_fake_zerotier_cli
write_config

# ---------------------------------------------------------------------------
# 1. A multi-word network name no longer produces a false authorization warning.
#    The status is read with "zerotier-cli get <nwid> status", not by parsing
#    positional "listnetworks" columns.
# ---------------------------------------------------------------------------
reset_state
out="$(FZT_STATUS=OK run_tool floating 2>&1)"
assert_contains "$out" "ZeroTier network $NWID is joined and authorized."
assert_not_contains "$out" "not yet authorized"
assert_not_contains "$out" "unexpected status"
assert_contains "$out" "Floating licensing mode is active."
grep -Fq "get $NWID status" "$ZT_LOG" || fail "status was not read via 'zerotier-cli get <nwid> status'"

# ---------------------------------------------------------------------------
# 2. ACCESS_DENIED is reported as an authorization problem naming the node id,
#    and the mode change still completes (warning, not fatal).
# ---------------------------------------------------------------------------
reset_state
out="$(FZT_STATUS=ACCESS_DENIED run_tool floating 2>&1)"
assert_contains "$out" "the controller has not authorized node $NODE_ID"
assert_contains "$out" "Floating licensing mode is active."

# ---------------------------------------------------------------------------
# 3. NOT_FOUND points at the network id / UNITY_NETWORK_ID, not the controller.
# ---------------------------------------------------------------------------
reset_state
out="$(FZT_STATUS=NOT_FOUND run_tool floating 2>&1)"
assert_contains "$out" "controller does not recognize network $NWID"
assert_contains "$out" "check UNITY_NETWORK_ID"
assert_not_contains "$out" "has not authorized node"

# ---------------------------------------------------------------------------
# 4. A network still negotiating after the timeout is described as such, not as
#    unauthorized.
# ---------------------------------------------------------------------------
reset_state
out="$(FZT_STATUS=REQUESTING_CONFIGURATION run_tool floating 2>&1)"
assert_contains "$out" "still negotiating with the controller"
assert_not_contains "$out" "has not authorized node"

# ---------------------------------------------------------------------------
# 5. An unexpected status is surfaced verbatim with a pointer to inspect it.
# ---------------------------------------------------------------------------
reset_state
out="$(FZT_STATUS=PORT_ERROR run_tool floating 2>&1)"
assert_contains "$out" "unexpected status 'PORT_ERROR'"
assert_contains "$out" "zerotier-cli listnetworks"

# ---------------------------------------------------------------------------
# 6. If the join never registers, the command fails clearly and mentions the
#    configured timeout.
# ---------------------------------------------------------------------------
reset_state
status=0
out="$(FZT_NEVER_REGISTERS=1 run_tool floating 2>&1)" || status=$?
[[ "$status" -ne 0 ]] || fail "a join that never registers should fail"
assert_contains "$out" "did not register after 2 seconds"

# ---------------------------------------------------------------------------
# 7. Rollback cannot undo ZeroTier changes, so a later failure reports the
#    node's residual state and the exact commands to reverse it.
# ---------------------------------------------------------------------------
reset_state
status=0
out="$(FZT_STATUS=OK FZT_INITIAL_ALLOW_MANAGED=0 FAKE_JQ_FAIL_SYSTEM_AFTER_FIRST=1 \
  run_tool floating 2>&1)" || status=$?
[[ "$status" -ne 0 ]] || fail "the forced post-install validation failure should exit non-zero"
assert_contains "$out" "original Unity configuration was restored"
assert_contains "$out" "ZeroTier changes made during this run were NOT reverted"
assert_contains "$out" "still joined to $NWID"
assert_contains "$out" "sudo zerotier-cli leave $NWID"
assert_contains "$out" "managed routes are still enabled"
assert_contains "$out" "zerotier-cli set $NWID allowManaged=0"
grep -Fq "set $NWID allowManaged=1" "$ZT_LOG" || fail "expected the tool to have enabled managed routes"

# ---------------------------------------------------------------------------
# 8. A successful join is NOT reported as un-reverted (the flags only speak up
#    on rollback).
# ---------------------------------------------------------------------------
reset_state
out="$(FZT_STATUS=OK FZT_INITIAL_ALLOW_MANAGED=0 run_tool floating 2>&1)"
assert_not_contains "$out" "were NOT reverted"

# ---------------------------------------------------------------------------
# 9. With UNITY_NETWORK_ALLOW_CHANGES off, the remediation prints a runnable
#    command using the real invocation path ($0), not a bare "unity-licensing-mode".
# ---------------------------------------------------------------------------
reset_state
status=0
out="$(ALLOW_CHANGES=false run_tool floating 2>&1)" || status=$?
[[ "$status" -ne 0 ]] || fail "floating should refuse to join when network changes are off"
assert_contains "$out" "UNITY_NETWORK_ALLOW_CHANGES=true $SCRIPT floating"
grep -Fq "join $NWID" "$ZT_LOG" && fail "the tool must not join when network changes are off"

# ---------------------------------------------------------------------------
# 10. --dry-run never calls join/set, but still explains what it would do.
# ---------------------------------------------------------------------------
reset_state
out="$(FZT_INITIAL_ALLOW_MANAGED=0 run_tool --dry-run floating 2>&1)"
assert_contains "$out" "Would join ZeroTier network $NWID"
if [[ -s "$ZT_LOG" ]] && grep -Eq '^(join|set) ' "$ZT_LOG"; then
  fail "dry-run invoked a mutating zerotier-cli command"
fi

# ---------------------------------------------------------------------------
# 11. Already joined with managed routes enabled: no join attempt at all.
# ---------------------------------------------------------------------------
reset_state
out="$(FZT_INITIAL_JOINED=1 FZT_INITIAL_ALLOW_MANAGED=1 run_tool floating 2>&1)"
assert_not_contains "$out" "Joining ZeroTier network"
assert_contains "$out" "Floating licensing mode is active."
grep -Fq "join $NWID" "$ZT_LOG" && fail "no join should happen when already a member"

printf 'zerotier checks passed\n'
