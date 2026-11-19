#!/usr/bin/env bash
# Lint QML (qmllint), optionally enforce formatting, and lint shell scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

cd "$(repo_root)" || exit 1

status=0

mapfile -t qml_files < <(find_qml .)
if [ "${#qml_files[@]}" -gt 0 ]; then
  if QMLLINT="$(qt_bin qmllint)"; then
    log "qmllint: ${#qml_files[@]} file(s)"
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
    if ! "$QMLLINT" "${import_args[@]}" "${qml_files[@]}"; then
      status=1
    fi
  else
    warn "qmllint not found; skipping QML lint"
  fi

  if QMLFORMAT="$(qt_bin qmlformat)"; then
    if [ "${FORMAT_STRICT:-0}" = "1" ]; then
      log "qmlformat: verifying formatting (strict)"
      for file in "${qml_files[@]}"; do
        if ! diff -u "$file" <("$QMLFORMAT" --ignore-settings "$file"); then
          fail "formatting drift in $file (run: make format)"
          status=1
        fi
      done
    fi
  fi
else
  log "no QML files yet - skipping QML lint"
fi

mapfile -t sh_files < <(find . -path ./.git -prune -o -type f -name '*.sh' -print | sort)
if [ "${#sh_files[@]}" -gt 0 ]; then
  if command -v shellcheck >/dev/null 2>&1; then
    log "shellcheck: ${#sh_files[@]} file(s)"
    if ! shellcheck -x "${sh_files[@]}"; then
      status=1
    fi
  else
    warn "shellcheck not found; skipping shell lint"
  fi
fi

if [ "$status" -eq 0 ]; then
  log "lint passed"
fi

exit "$status"
