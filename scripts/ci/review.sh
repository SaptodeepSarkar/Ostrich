#!/usr/bin/env bash
# Repository hygiene review: whitespace, EOF newlines, conflict markers, large
# files, generated files, and accidental secret material.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

cd "$(repo_root)" || exit 1

status=0
max_bytes=$((2 * 1024 * 1024))
secret_re='gh[p]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}'

mapfile -t files < <(git ls-files)
if [ "${#files[@]}" -eq 0 ]; then
  skip "no tracked files"
fi

text_files=()
for file in "${files[@]}"; do
  if [ -f "$file" ] && grep -Iq . "$file" 2>/dev/null; then
    text_files+=("$file")
  fi
done

log "reviewing ${#text_files[@]} tracked text file(s)"

for file in "${text_files[@]}"; do
  case "$file" in
    *.qmlc | *.jsc | *.pyc | .DS_Store | Thumbs.db)
      fail "generated file is tracked: $file"
      status=1
      continue
      ;;
  esac

  size="$(stat -c %s "$file")"
  if [ "$size" -gt "$max_bytes" ]; then
    fail "file is larger than 2 MiB: $file (${size} bytes)"
    status=1
  fi

  case "$file" in
    *.md) ;;
    *)
      whitespace_hits="$(grep -nE '[[:blank:]]+$' "$file" || true)"
      if [ -n "$whitespace_hits" ]; then
        fail "trailing whitespace in $file"
        printf '%s\n' "$whitespace_hits"
        status=1
      fi
      ;;
  esac

  if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
    fail "missing final newline: $file"
    status=1
  fi

  conflict_hits="$(grep -nE '^(<<<<<<< |=======$|>>>>>>> )' "$file" || true)"
  if [ -n "$conflict_hits" ]; then
    fail "unresolved merge conflict markers in $file"
    printf '%s\n' "$conflict_hits"
    status=1
  fi

  if [ "$file" != "scripts/ci/review.sh" ]; then
    secret_hits="$(grep -nE "$secret_re" "$file" || true)"
    if [ -n "$secret_hits" ]; then
      fail "possible secret material in $file"
      printf '%s\n' "$secret_hits"
      status=1
    fi
  fi

  case "$file" in
    scripts/ci/*) ;;
    *.qml | *.sh | *.js)
      todo_hits="$(grep -nE '(TODO|FIXME)' "$file" || true)"
      if [ -n "$todo_hits" ]; then
        warn "TODO/FIXME in $file (allowed, but resolve before release)"
      fi
      ;;
  esac
done

if [ "$status" -eq 0 ]; then
  log "review passed"
fi

exit "$status"
