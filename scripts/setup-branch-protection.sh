#!/usr/bin/env bash
# Apply branch protection and repository merge settings.
#
# Usage:
#   scripts/setup-branch-protection.sh [owner/repo]
#
# Requires the GitHub CLI, authenticated with admin access to the repository.
set -euo pipefail

REPO="${1:-${GH_REPO:-}}"
if [ -z "$REPO" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    printf 'error: gh is required (or pass owner/repo as the first argument)\n' >&2
    exit 1
  fi
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

CHECKS=("validate" "lint" "qml-compile" "test" "review" "CI Success")

json_list() {
  local out="" item
  for item in "$@"; do
    out="${out}${out:+,}\"${item}\""
  done
  printf '%s' "$out"
}

contexts="$(json_list "${CHECKS[@]}")"

apply_protection() {
  local branch="$1"
  local payload="$2"
  printf '%s' "$payload" | gh api \
    --method PUT \
    "repos/${REPO}/branches/${branch}/protection" \
    --header 'Accept: application/vnd.github+json' \
    --input - >/dev/null
  printf 'protected: %s\n' "$branch"
}

printf 'applying protection to %s\n' "$REPO"

# main: pull requests only, all quality gates, up-to-date branches.
read -r -d '' main_payload <<EOF || true
{
  "required_status_checks": {
    "strict": true,
    "contexts": [${contexts}]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
EOF
apply_protection main "$main_payload"

# test: release candidates. Pull requests must pass CI; the sync bot may push
# main back into test directly.
read -r -d '' test_payload <<EOF || true
{
  "required_status_checks": {
    "strict": true,
    "contexts": [${contexts}]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
EOF
apply_protection test "$test_payload"

# dev: integration branch. No pull request requirement, but no history rewrites.
read -r -d '' dev_payload <<EOF || true
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": false
}
EOF
apply_protection dev "$dev_payload"

# Merge strategy: merge commits only (keeps test/main ancestry stable so the
# sync workflow can fast-forward/merge cleanly). Never delete permanent branches.
gh api --method PATCH "repos/${REPO}" \
  --field allow_merge_commit=true \
  --field allow_squash_merge=false \
  --field allow_rebase_merge=false \
  --field delete_branch_on_merge=false \
  --field allow_auto_merge=true \
  --field allow_update_branch=true \
  >/dev/null

printf 'repository merge settings updated\n'
printf 'done: %s\n' "$REPO"
