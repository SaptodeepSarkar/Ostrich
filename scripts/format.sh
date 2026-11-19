#!/usr/bin/env bash
# Format all QML sources in place.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci/lib.sh
source "$SCRIPT_DIR/ci/lib.sh"

cd "$(repo_root)" || exit 1

if ! QMLFORMAT="$(qt_bin qmlformat)"; then
  fail "qmlformat not found (install qt6-declarative)"
  exit 1
fi

mapfile -t qml_files < <(find_qml .)
if [ "${#qml_files[@]}" -eq 0 ]; then
  skip "no QML files yet"
fi

"$QMLFORMAT" --inplace "${qml_files[@]}"
log "formatted ${#qml_files[@]} QML file(s)"
