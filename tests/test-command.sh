#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
SCRIPT="$PROJECT_DIR/bin/unity-licensing-mode"

bash -n "$SCRIPT"

help_output="$("$SCRIPT" --help)"
printf '%s\n' "$help_output" | grep -q "Usage: unity-licensing-mode"
printf '%s\n' "$help_output" | grep -q "floating"

if "$SCRIPT" unsupported-command >/dev/null 2>&1; then
  printf 'unsupported command unexpectedly succeeded\n' >&2
  exit 1
fi

printf 'command checks passed\n'
