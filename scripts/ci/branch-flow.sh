#!/usr/bin/env bash
# Enforce the promotion flow and the version bump on release pull requests.
#
#   dev  -> test : version must increase and have a CHANGELOG entry
#   test -> main : version must increase relative to main and have a CHANGELOG entry
#
# Inputs (environment):
#   BASE_BRANCH  target branch of the pull request
#   HEAD_BRANCH  source branch of the pull request
#   BASE_SHA     commit SHA the pull request is based on (for reading VERSION)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

cd "$(repo_root)" || exit 1

BASE="${BASE_BRANCH:?BASE_BRANCH is required}"
HEAD="${HEAD_BRANCH:?HEAD_BRANCH is required}"
BASE_SHA="${BASE_SHA:-origin/${BASE}}"

case "$BASE" in
  test)
    if [ "$HEAD" != "dev" ]; then
      fail "only 'dev' may be merged into 'test' (got '$HEAD')"
      exit 1
    fi
    ;;
  main)
    if [ "$HEAD" != "test" ]; then
      fail "only 'test' may be merged into 'main' (got '$HEAD')"
      exit 1
    fi
    ;;
  *)
    log "no branch-flow rules for base '$BASE'"
    exit 0
    ;;
esac

new_version="$(tr -d '[:space:]' < VERSION)"
old_version="$(git show "${BASE_SHA}:VERSION" 2>/dev/null | tr -d '[:space:]' || true)"

if [ -z "$old_version" ]; then
  fail "cannot read VERSION from ${BASE_SHA}"
  exit 1
fi

if [ "$new_version" = "$old_version" ]; then
  fail "VERSION was not bumped (${old_version} -> ${new_version}); release PRs must bump VERSION"
  exit 1
fi

highest="$(printf '%s\n%s\n' "$old_version" "$new_version" | sort -V | tail -n 1)"
if [ "$highest" != "$new_version" ]; then
  fail "VERSION must increase (${old_version} -> ${new_version})"
  exit 1
fi

if ! grep -qE "^## \[${new_version//./\\.}\]" CHANGELOG.md; then
  fail "CHANGELOG.md has no entry for ${new_version}"
  exit 1
fi

log "branch flow ok: ${HEAD} -> ${BASE}, version ${old_version} -> ${new_version}"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Branch flow"
    echo
    echo "- Promotion: \`${HEAD}\` -> \`${BASE}\`"
    echo "- Version: \`${old_version}\` -> \`${new_version}\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi
