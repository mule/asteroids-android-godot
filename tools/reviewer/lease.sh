#!/usr/bin/env bash
# Mutual exclusion for PR reviewer agents, arbitrated by GitHub.
#
# The mutex primitive itself (a namespaced git ref as an atomic
# compare-and-swap) lives in tools/pool/lock.sh, shared with every agent
# pool. This file is the reviewer pool's policy on top of it: which
# namespaces it uses, what "claimable" means for a PR, the review-passed
# sha pin, and reviewer-specific sweep/holders reporting.
#
# Usage:
#   lease.sh claimable            # PR numbers nobody holds (one per line)
#   lease.sh claim <pr>           # exit 0 + echo <pr> if the lock was won
#   lease.sh release <pr>         # drop the lock (always run, even on failure)
#   lease.sh mark-passed <pr>     # record "reviewed clean at this sha"
#   lease.sh mergeable            # already reviewed, waiting only on a sign-off
#   lease.sh sweep                # break leases older than the TTL
#   lease.sh holders              # show every currently-held lock
set -euo pipefail

SLUG="${REVIEW_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
AGENT="${REVIEWER_ID:-$(hostname)-$$}"
TTL_MIN="${REVIEW_LEASE_TTL_MIN:-90}"

# lease.sh's own CLI and env contract (REVIEW_REPO, REVIEWER_ID,
# REVIEW_LEASE_TTL_MIN) is public: a live Orca automation and
# tools/reviewer/*.md call it as-is and must not change. lock.sh's contract
# (POOL_REPO, POOL_AGENT_ID) is a separate, internal surface for the shared
# primitive. Export the values lease.sh already resolved under lock.sh's
# names so every $LOCK call below uses the same repo and identity, instead of
# lock.sh re-deriving its own (an extra `gh repo view` and a different
# hostname-pid identity per invocation).
export POOL_REPO="$SLUG" POOL_AGENT_ID="$AGENT"

# Anchored to this script's own location, not cwd: lease.sh is invoked from
# various places (coordinator loop, tests), and a cwd-relative path here
# would 127 under set -e the moment something ran it from elsewhere,
# breaking release()'s "always run, even on failure" contract below.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK="$SCRIPT_DIR/../pool/lock.sh"
NS=reviewer-locks
NS_PASSED=reviewer-passed

held_prs() { $LOCK held "$NS" | sed 's/^pr-//'; }

# "pr<TAB>sha" for every PR a reviewer has already cleared, at the exact sha it
# cleared. Storing the sha is what lets a PR re-enter the queue when new commits
# land on it, without re-reviewing an unchanged branch every 30 minutes.
passed_at() { $LOCK shas "$NS_PASSED" | sed 's/^pr-//'; }

mark_passed() {
  local pr=$1 sha
  sha=$(gh api "repos/$SLUG/pulls/$pr" -q .head.sha)
  $LOCK release "$NS_PASSED" "pr-$pr" >/dev/null
  $LOCK claim "$NS_PASSED" "pr-$pr" "$sha" >/dev/null
  gh pr edit "$pr" --repo "$SLUG" --add-label review-passed >/dev/null 2>&1 || true
}

# Open PRs that are unlocked, not parked for a human, and not already cleared
# at their current head sha.
claimable() {
  local held open passed
  held=$(held_prs)
  passed=$(passed_at)
  open=$(gh pr list --repo "$SLUG" --state open --limit 100 \
           --json number,isDraft,labels,headRefOid \
           -q '.[] | select(.isDraft | not)
                   | select([.labels[].name] | index("review-blocked") | not)
                   | "\(.number)\t\(.headRefOid)"')
  printf '%s\n' "$open" | awk -v held="$held" -v passed="$passed" '
    BEGIN {
      n = split(held, h, /[ \n]+/);      for (i=1;i<=n;i++) if (h[i] != "") locked[h[i]] = 1
      n = split(passed, p, /\n/)
      for (i=1;i<=n;i++) { split(p[i], kv, /\t/); if (kv[1] != "") clean[kv[1]] = kv[2] }
    }
    NF && !locked[$1] && clean[$1] != $2 { print $1 }'
}

# Reviewed and clean, parked on review-passed until a human approves. These
# need a re-check of the merge gate, not another review.
mergeable() {
  gh pr list --repo "$SLUG" --state open --limit 100 --json number,labels \
    -q '.[] | select([.labels[].name] | index("review-passed"))
            | select([.labels[].name] | index("review-blocked") | not)
            | .number'
}

claim() {
  local pr=$1 sha
  sha=$(gh api "repos/$SLUG/pulls/$pr" -q .head.sha)
  $LOCK claim "$NS" "pr-$pr" "$sha" >/dev/null || return 1
  $LOCK note "$pr" "Review lease held by \`$AGENT\`."
  gh pr edit "$pr" --repo "$SLUG" --add-label review-in-progress >/dev/null 2>&1 || true
  echo "$pr"
}

release() {
  local pr=$1
  # lock.sh's own release always exits 0 by contract, but the invocation
  # itself can still fail (e.g. the helper is missing -> 127). Guard it so
  # this always reaches the label removal, matching the "always run, even
  # on failure" contract callers rely on.
  $LOCK release "$NS" "pr-$pr" || true
  gh pr edit "$pr" --repo "$SLUG" --remove-label review-in-progress >/dev/null 2>&1 || true
}

# Lease-holder marker comments. lock.sh's `note` (via `claim`, above) writes
# "<!-- pool-lease", the namespace-generic marker. Comments already posted on
# live PRs before this refactor carry the old "<!-- review-lease" marker, and
# this repo's stale-lease detection below must keep recognising those or a
# crashed reviewer's lock would silently never expire again. Match both;
# nothing here ever writes the old marker any more.
LEASE_MARKER_QUERY='.[] | select(.body | test("<!-- (review|pool)-lease")) | '

# A crashed agent leaves its lock behind. Break locks whose newest lease
# comment is older than TTL_MIN so the PR re-enters the pool.
sweep() {
  local pr stamp age_min now open_keys

  # Merged and closed PRs leave lock and passed refs behind. gc both
  # namespaces down to the open queue so they stay its size, not the repo's
  # history.
  open_keys=$(gh pr list --repo "$SLUG" --state open --limit 100 --json number -q '.[].number' | sed 's/^/pr-/')
  $LOCK gc "$NS" $open_keys
  $LOCK gc "$NS_PASSED" $open_keys

  now=$(date -u +%s)
  for pr in $(held_prs); do
    stamp=$(gh api "repos/$SLUG/issues/$pr/comments" --paginate \
              -q "${LEASE_MARKER_QUERY}.created_at" \
            | tail -1)
    [ -n "$stamp" ] || continue
    age_min=$(( (now - $(date -u -d "$stamp" +%s)) / 60 ))
    if [ "$age_min" -ge "$TTL_MIN" ]; then
      echo "breaking stale lease on #$pr (${age_min}m old)"
      release "$pr"
    fi
  done
}

holders() {
  local pr
  for pr in $(held_prs); do
    printf '#%s\t%s\n' "$pr" "$(gh api "repos/$SLUG/issues/$pr/comments" --paginate \
      -q "${LEASE_MARKER_QUERY}.body" | tail -1 | head -1)"
  done
}

case "${1:-}" in
  claimable)   claimable ;;
  mergeable)   mergeable ;;
  mark-passed) mark_passed "$2" ;;
  claim)     claim "$2" ;;
  release)   release "$2" ;;
  sweep)     sweep ;;
  holders)   holders ;;
  *) echo "usage: $0 {claimable|mergeable|claim <pr>|mark-passed <pr>|release <pr>|sweep|holders}" >&2; exit 2 ;;
esac
