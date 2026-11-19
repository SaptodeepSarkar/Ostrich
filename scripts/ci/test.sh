#!/usr/bin/env bash
# Run Qt Quick Test suites (tests/**/tst_*.qml).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

cd "$(repo_root)" || exit 1

if [ ! -d tests ]; then
  skip "no tests/ directory yet"
fi

mapfile -t test_files < <(find tests -type f -name 'tst_*.qml' | sort)
if [ "${#test_files[@]}" -eq 0 ]; then
  skip "no Qt Quick Test files (tests/**/tst_*.qml) yet"
fi

if ! QMLTESTRUNNER="$(qt_bin qmltestrunner)"; then
  skip "qmltestrunner not available"
fi

status=0
test_dirs=()
for file in "${test_files[@]}"; do
  test_dirs+=("$(dirname "$file")")
done
mapfile -t test_dirs < <(printf '%s\n' "${test_dirs[@]}" | sort -u)

for dir in "${test_dirs[@]}"; do
  log "qmltestrunner: $dir (${#test_files[@]} test file(s) total)"
  if ! QT_QPA_PLATFORM=offscreen "$QMLTESTRUNNER" -input "$dir" -import .; then
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  log "tests passed"
fi

exit "$status"
