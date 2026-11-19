#!/usr/bin/env bash
# Opt-in Quickshell smoke test: launch the shell headless and fail on load errors.
#
# Requires Quickshell (`qs`) and its QML modules. The CI job is gated behind the
# repository variable ENABLE_QUICKSHELL_SMOKE=true because building Quickshell
# from the AUR is slow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

cd "$(repo_root)" || exit 1

if ! command -v qs >/dev/null 2>&1; then
  skip "Quickshell (qs) is not installed"
fi

config="${QUICKSHELL_CONFIG:-}"
if [ -z "$config" ]; then
  if [ -f shell/shell.qml ]; then
    config="shell/shell.qml"
  elif [ -f shell.qml ]; then
    config="shell.qml"
  else
    skip "no shell entry point found (expected shell/shell.qml or shell.qml)"
  fi
fi

log "launching Quickshell headless: $config"
log_file="$(mktemp)"

set +e
QT_QPA_PLATFORM=offscreen timeout 25 qs -p "$config" >"$log_file" 2>&1
exit_code=$?
set -e

cat "$log_file"

if grep -qiE 'ReferenceError|TypeError|is not a type|Failed to load component|qml: .*error' "$log_file"; then
  fail "Quickshell reported QML load errors"
  exit 1
fi

# 124 is the timeout: the shell kept running for the whole window, which is the goal.
if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 124 ]; then
  fail "Quickshell exited with code ${exit_code}"
  exit 1
fi

log "smoke test passed"
