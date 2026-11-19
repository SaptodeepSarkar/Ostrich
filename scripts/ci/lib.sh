#!/usr/bin/env bash
# Shared helpers for the Ostrich CI scripts.
# shellcheck shell=bash

set -euo pipefail

log() { printf '[ci] %s\n' "$*"; }
warn() { printf '[ci:warn] %s\n' "$*" >&2; }
fail() { printf '[ci:error] %s\n' "$*" >&2; }
skip() {
  printf '[ci:skip] %s\n' "$*"
  exit 0
}

# Resolve a Qt tool that may live outside PATH (Arch ships them in /usr/lib/qt6/bin).
qt_bin() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
  elif [ -x "/usr/lib/qt6/bin/$tool" ]; then
    printf '/usr/lib/qt6/bin/%s\n' "$tool"
  elif [ -x "/usr/lib/qt6/bin/${tool}6" ]; then
    printf '/usr/lib/qt6/bin/%s6\n' "$tool"
  else
    return 1
  fi
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Print all QML sources below $1 (default: repo root).
find_qml() {
  local root="${1:-.}"
  find "$root" \
    \( -name .git -o -name build -o -name .cache -o -name node_modules \) -prune -o \
    -type f -name '*.qml' -print | sort
}
