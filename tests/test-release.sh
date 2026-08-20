#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
SCRIPT="$PROJECT_DIR/bin/unity-licensing-mode"

version="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$("$SCRIPT" --version)" == "unity-licensing-mode $version" ]]
grep -q "## \[$version\]" "$PROJECT_DIR/CHANGELOG.md"
grep -q "vMAJOR.MINOR.PATCH" "$PROJECT_DIR/CHANGELOG.md"

release_tag=""
if [[ "$#" -gt 0 ]]; then
  release_tag="$1"
fi
if [[ -n "$release_tag" ]]; then
  if [[ "$release_tag" != "v$version" ]]; then
    printf 'release tag %s does not match VERSION %s\n' "$release_tag" "$version" >&2
    exit 1
  fi
fi

printf 'release checks passed\n'
