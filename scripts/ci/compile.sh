#!/usr/bin/env bash
# Static compile/type check for QML sources.
#
# True "does the shell load" compilation needs Quickshell's QML modules, which are
# installed by the opt-in smoke job. This script always parses every QML file and
# type-checks the files that do not depend on Quickshell.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

cd "$(repo_root)" || exit 1

mapfile -t qml_files < <(find_qml .)
if [ "${#qml_files[@]}" -eq 0 ]; then
  skip "no QML files yet"
fi

status=0

# 1. Syntax: qmlformat parses the document and fails on invalid QML.
if QMLFORMAT="$(qt_bin qmlformat)"; then
  log "parsing ${#qml_files[@]} QML file(s)"
  for file in "${qml_files[@]}"; do
    if ! parse_error="$("$QMLFORMAT" --ignore-settings "$file" 2>&1 >/dev/null)"; then
      fail "QML parse error in $file"
      printf '%s\n' "$parse_error" >&2
      status=1
    fi
  done
else
  warn "qmlformat not found; cannot verify QML syntax"
fi

# 2. Type check everything that does not need the Quickshell module.
if QMLLINT="$(qt_bin qmllint)"; then
  import_args=()
  if [ -d shell ]; then
    import_args+=(-I shell)
  fi
  if [ -d src ]; then
    import_args+=(-I src)
  fi
  if [ -n "${QUICKSHELL_IMPORT_PATH:-}" ] && [ -d "${QUICKSHELL_IMPORT_PATH}" ]; then
    import_args+=(-I "${QUICKSHELL_IMPORT_PATH}")
  fi

  plain_files=()
  quickshell_files=()
  for file in "${qml_files[@]}"; do
    if grep -qE '^[[:space:]]*import[[:space:]]+Quickshell' "$file"; then
      quickshell_files+=("$file")
    else
      plain_files+=("$file")
    fi
  done

  if [ "${#plain_files[@]}" -gt 0 ]; then
    log "type-checking ${#plain_files[@]} Quickshell-independent file(s)"
    if ! "$QMLLINT" "${import_args[@]}" "${plain_files[@]}"; then
      status=1
    fi
  fi

  if [ "${#quickshell_files[@]}" -gt 0 ]; then
    if [ -n "${QUICKSHELL_IMPORT_PATH:-}" ] && [ -d "${QUICKSHELL_IMPORT_PATH}" ]; then
      log "type-checking ${#quickshell_files[@]} Quickshell file(s)"
      if ! "$QMLLINT" "${import_args[@]}" "${quickshell_files[@]}"; then
        status=1
      fi
    else
      warn "skipping ${#quickshell_files[@]} file(s) that import Quickshell (set QUICKSHELL_IMPORT_PATH or run the smoke job)"
    fi
  fi
else
  warn "qmllint not found; skipping QML type check"
fi

if [ "$status" -eq 0 ]; then
  log "compile check passed"
fi

exit "$status"
