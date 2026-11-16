#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
SCRIPT="$PROJECT_DIR/bin/unity-licensing-mode"

bash -n "$SCRIPT"

help_output="$("$SCRIPT" --help)"
printf '%s\n' "$help_output" | grep -q "Usage: unity-licensing-mode"
printf '%s\n' "$help_output" | grep -q "floating"
printf '%s\n' "$help_output" | grep -q "doctor"
printf '%s\n' "$help_output" | grep -q -- "--dry-run"

version_output="$("$SCRIPT" --version)"
[[ "$version_output" == "unity-licensing-mode $(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")" ]]

command_version_output="$("$SCRIPT" version)"
[[ "$command_version_output" == "$version_output" ]]

if "$SCRIPT" unsupported-command >/dev/null 2>&1; then
  printf 'unsupported command unexpectedly succeeded\n' >&2
  exit 1
fi

# Exercise the production predicate without invoking mode changes or touching
# real processes. The stub applies pgrep's regex to representative command lines.
eval "$(sed -n '/^unity_running() {$/,/^}$/p' "$SCRIPT")"
pgrep() {
  [[ "$1" == "-f" ]]
  printf '%s\n' "$TEST_PROCESS_COMMAND" | grep -Eq -- "$2"
}

for TEST_PROCESS_COMMAND in \
  '/Applications/Unity Hub.app/Contents/MacOS/Unity Hub' \
  '/Applications/Unity Hub.app/Contents/MacOS/Unity Hub --some-option' \
  '/Applications/Unity/Hub/Editor/6000.2.9f1/Unity.app/Contents/MacOS/Unity -projectpath /tmp/project' \
  '/Applications/Unity/Hub/Editor/6000.2.9f1/Unity.app/Contents/MacOS/Unity'; do
  unity_running || { printf 'missed app executable: %s\n' "$TEST_PROCESS_COMMAND" >&2; exit 1; }
done

for TEST_PROCESS_COMMAND in \
  '/Applications/Unity Hub.app/Contents/Frameworks/UnityLicensingClient_V1.app/Contents/MacOS/Unity.Licensing.Client' \
  '/Applications/Unity Hub.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler' \
  '/Applications/Unity Hub.app/Contents/Frameworks/Unity Hub Helper.app/Contents/MacOS/Unity Hub Helper' \
  '/Applications/Unity/Hub/Editor/6000.2.9f1/Unity.app/Contents/Resources/PackageManager/Server/UnityPackageManager' \
  '/Applications/Unity/Hub/Editor/6000.2.9f1/Unity.app/Contents/Tools/UnityShaderCompiler' \
  '/bin/bash inspect /Applications/Unity Hub.app/Contents/MacOS/Unity Hub' \
  '/bin/bash inspect /Applications/Unity/Hub/Editor/6000.2.9f1/Unity.app/Contents/MacOS/Unity' \
  '/Applications/Unity Hub.app/Contents/MacOS/Unity HubOther' \
  '/Applications/Unity/Hub/Editor/6000.2.9f1/UnityXapp/Contents/MacOS/Unity' \
  '' \
  '/Applications/Unity/Hub/Editor/6000.2.9f1/Unity.app/Contents/MacOS/UnityOther'; do
  if unity_running; then
    printf 'mistook helper or argument for an app: %s\n' "$TEST_PROCESS_COMMAND" >&2
    exit 1
  fi
done

printf 'command checks passed\n'
