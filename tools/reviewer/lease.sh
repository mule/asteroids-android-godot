#!/usr/bin/env bash
# Mutual exclusion for PR reviewer agents, arbitrated by GitHub.
#
# The lock is a git ref under refs/reviewer-locks/. Ref creation is an atomic
# compare-and-swap on GitHub's side: the first agent to POST /git/refs wins,
# every later agent gets HTTP 422 "Reference already exists". No coordinator,
# no polling window, no double-review.
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
LOCK_PREFIX="reviewer-locks/pr-"
PASS_PREFIX="reviewer-passed/pr-"

lock_ref() { printf 'refs/%s%s' "$LOCK_PREFIX" "$1"; }

held_prs() {
  gh api "repos/$SLUG/git/matching-refs/${LOCK_PREFIX%pr-}" -q '.[].ref' 2>/dev/null \
    | sed "s|^refs/${LOCK_PREFIX}||" || true
}

# "pr<TAB>sha" for every PR a reviewer has already cleared, at the exact sha it
# cleared. Storing the sha is what lets a PR re-enter the queue when new commits
# land on it, without re-reviewing an unchanged branch every 30 minutes.
passed_at() {
  gh api "repos/$SLUG/git/matching-refs/${PASS_PREFIX%pr-}" 2>/dev/null \
    | jq -r --arg p "refs/${PASS_PREFIX}" '.[] | "\(.ref | ltrimstr($p))\t\(.object.sha)"' \
    || true
}

mark_passed() {
  local pr=$1 sha
  sha=$(gh api "repos/$SLUG/pulls/$pr" -q .head.sha)
  gh api -X DELETE "repos/$SLUG/git/refs/${PASS_PREFIX}${pr}" >/dev/null 2>&1 || true
  gh api "repos/$SLUG/git/refs" -f ref="refs/${PASS_PREFIX}${pr}" -f sha="$sha" >/dev/null
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
  gh api "repos/$SLUG/git/refs" -f ref="$(lock_ref "$pr")" -f sha="$sha" >/dev/null 2>&1 || return 1
  gh pr comment "$pr" --repo "$SLUG" >/dev/null --body \
    "<!-- review-lease agent=$AGENT at=$(date -u +%Y-%m-%dT%H:%M:%SZ) -->
🤖 Review lease held by \`$AGENT\`."
  gh pr edit "$pr" --repo "$SLUG" --add-label review-in-progress >/dev/null 2>&1 || true
  echo "$pr"
}

release() {
  local pr=$1
  gh api -X DELETE "repos/$SLUG/git/refs/${LOCK_PREFIX}${pr}" >/dev/null 2>&1 || true
  gh pr edit "$pr" --repo "$SLUG" --remove-label review-in-progress >/dev/null 2>&1 || true
}

# A crashed agent leaves its lock behind. Break locks whose newest lease
# comment is older than TTL_MIN so the PR re-enters the pool.
sweep() {
  local pr stamp age_min now open
  now=$(date -u +%s)

  # Merged and closed PRs leave lock and passed refs behind. Collect them so the
  # lock namespace stays the size of the open queue, not the repo's history.
  open=" $(gh pr list --repo "$SLUG" --state open --limit 100 --json number -q '.[].number' | tr '\n' ' ')"
  for pr in $(held_prs) $(passed_at | cut -f1); do
    case "$open" in
      *" $pr "*) ;;
      *) gh api -X DELETE "repos/$SLUG/git/refs/${LOCK_PREFIX}${pr}" >/dev/null 2>&1 || true
         gh api -X DELETE "repos/$SLUG/git/refs/${PASS_PREFIX}${pr}" >/dev/null 2>&1 || true ;;
    esac
  done

  for pr in $(held_prs); do
    stamp=$(gh api "repos/$SLUG/issues/$pr/comments" --paginate \
              -q '.[] | select(.body | contains("<!-- review-lease")) | .created_at' \
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
      -q '.[] | select(.body | contains("<!-- review-lease")) | .body' | tail -1 | head -1)"
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
