#!/usr/bin/env bash
# Validate repository metadata: required files, VERSION format, CHANGELOG entry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

cd "$(repo_root)" || exit 1

status=0

required_files=(
  VERSION
  CHANGELOG.md
  README.md
  AGENTS.md
  PRD.md
  LICENSE
  .github/workflows/ci.yml
  .github/workflows/release.yml
)

for file in "${required_files[@]}"; do
  if [ ! -f "$file" ]; then
    fail "missing required file: $file"
    status=1
  fi
done

version="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  fail "VERSION must be plain SemVer MAJOR.MINOR.PATCH without a leading 'v' (got: '$version')"
  status=1
fi

if ! grep -qE "^## \[${version//./\\.}\]" CHANGELOG.md; then
  fail "CHANGELOG.md has no '## [$version]' section"
  status=1
fi

if [ "$status" -eq 0 ]; then
  log "repository metadata valid (version $version)"
fi

exit "$status"
