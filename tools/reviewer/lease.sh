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
ROSTER="$SCRIPT_DIR/../pool/roster.sh"
NS=reviewer-locks
NS_PASSED=reviewer-passed

held_prs() { $LOCK held "$NS" | sed 's/^pr-//'; }

# "pr<TAB>sha" for every PR a reviewer has already cleared, at the exact sha it
# cleared. Storing the sha is what lets a PR re-enter the queue when new commits
# land on it, without re-reviewing an unchanged branch every 30 minutes.
passed_at() { $LOCK shas "$NS_PASSED" | sed 's/^pr-//'; }

# The roster tier a reviewer agent runs at: the HIGHEST `review` row's tier.
# Read from the roster, never hardcoded -- roster.tsv is the single place the
# tier ladder is declared, and a literal here would silently outlive an edit
# to it. With several review rows the highest is the safe answer: stamping a
# higher tier only makes `reviewers-above` emptier, i.e. makes the gate hold
# for a human, which is the direction an ambiguity must fail in.
reviewer_tier() {
  local t
  t=$($ROSTER reviewers-above 0 | awk -F'\t' '{print $4+0}' | sort -n | tail -1) || return 1
  case "$t" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$t"
}

# Force the PR's impl-tier label to <tier>, and PROVE it afterwards by
# re-reading the labels. An unverified `gh pr edit` is the failure this whole
# branch exists to stamp out: --add-label exits non-zero when the label does
# not exist in the repo, and a swallowed failure here would leave the PR
# declaring the tier that built it while a same-or-higher tier had in fact
# written commits on it.
stamp_tier() {
  local pr=$1 tier=$2 labels l
  if ! labels=$(gh pr view "$pr" --repo "$SLUG" --json labels -q '.labels[].name'); then
    echo "lease.sh: cannot read #$pr's labels (gh pr view error) - refusing to record a pass" >&2
    return 1
  fi
  for l in $labels; do
    case "$l" in
      "impl-tier:$tier") ;;
      impl-tier:*)
        if ! gh pr edit "$pr" --repo "$SLUG" --remove-label "$l" >/dev/null; then
          echo "lease.sh: cannot remove stale '$l' from #$pr - refusing to record a pass" >&2
          return 1
        fi ;;
    esac
  done
  if ! gh pr edit "$pr" --repo "$SLUG" --add-label "impl-tier:$tier" >/dev/null; then
    echo "lease.sh: cannot add impl-tier:$tier to #$pr - refusing to record a pass" >&2
    return 1
  fi
  if ! labels=$(gh pr view "$pr" --repo "$SLUG" --json labels -q '.labels[].name'); then
    echo "lease.sh: cannot re-read #$pr's labels to verify impl-tier:$tier - refusing to record a pass" >&2
    return 1
  fi
  case " $(printf '%s ' $labels)" in
    *" impl-tier:$tier "*) return 0 ;;
    *) echo "lease.sh: #$pr still does not carry impl-tier:$tier after the edit - refusing to record a pass" >&2
       return 1 ;;
  esac
}

# Record "reviewed clean at this sha" -- and enforce the tier invariant while
# doing it.
#
# REVIEWER.md step 3 tells the reviewer to push its fixes on essentially every
# PR, and step 5 then asks it to remember to stamp its own `impl-tier:<n>`
# first. "Forgot to stamp" was therefore the DEFAULT path, and the result is a
# tier-3 reviewer clearing its own commits under the tier-1 label the
# implementer left behind -- the exact thing the tier ladder exists to
# prevent, arrived at by doing nothing.
#
# No authorship lookup is needed to detect it: `claim` already pinned the head
# sha the lease was taken at in refs/reviewer-locks/pr-N. If the PR's head has
# moved since, commits were pushed under this lease, so this reviewer is now
# an author of the code it is about to clear. AUTO-STAMP rather than refuse:
# refusing would leave the correct label to the same agent that just forgot
# it, and nothing stops it stamping a tier LOWER than its own, so refusal
# enforces nothing mechanically. Stamping from the roster does, and the worst
# case is a gate that holds for a human.
#
# A missing lock ref is refused, not waved through: with nothing to compare
# against, "the head did not move" is a guess, and guessing here is exactly
# the fail-open this replaces. (It also means mark-passed was called without
# a lease, which is not allowed anyway.)
mark_passed() {
  local pr=$1 sha claimed tier
  if ! sha=$(gh api "repos/$SLUG/pulls/$pr" -q .head.sha) || [ -z "$sha" ]; then
    echo "lease.sh: cannot read #$pr's head sha (gh api error) - refusing to record a pass" >&2
    return 1
  fi
  claimed=$($LOCK sha "$NS" "pr-$pr")
  if [ -z "$claimed" ]; then
    echo "lease.sh: no $NS lease recorded for #$pr - refusing to record a pass; claim the PR first (a pass with no lease cannot be checked for reviewer-authored commits)" >&2
    return 1
  fi
  if [ "$claimed" != "$sha" ]; then
    if ! tier=$(reviewer_tier); then
      echo "lease.sh: #$pr's head moved under this lease but roster.sh gave no review tier - refusing to record a pass" >&2
      return 1
    fi
    echo "lease.sh: #$pr head moved $claimed -> $sha under this lease; the reviewer pushed commits, stamping impl-tier:$tier" >&2
    stamp_tier "$pr" "$tier" || return 1
  fi
  $LOCK release "$NS_PASSED" "pr-$pr" >/dev/null
  $LOCK claim "$NS_PASSED" "pr-$pr" "$sha" >/dev/null
  gh pr edit "$pr" --repo "$SLUG" --add-label review-passed >/dev/null 2>&1 || true
}

# Open PRs that are unlocked, not parked for a human, not held by an operator,
# and not already cleared at their current head sha.
#
# `hold` is excluded alongside `review-blocked`. merge-gate.sh honours `hold`
# as its FIRST rule and the briefs advertise it as the operator's emergency
# brake, but this filter used to ignore it entirely: a held PR was still
# claimed, reviewed, commented on and pushed to, and only then bounced at the
# gate. A brake that stops the merge but not the work is not the brake its
# name promises, so it stops the work here too.
claimable() {
  local held open passed
  # held_prs() pipes lock.sh's held() through sed; under pipefail, held()
  # returning non-zero (the gh api call for reviewer-locks itself failed --
  # auth/rate-limit/network) propagates through that pipe, and this used to
  # be a plain assignment, so `set -e` would kill the whole function
  # silently: exit 1, no stderr, no partial output. This is the LIVE
  # reviewer pool's claim path on an enabled automation, so silent death is
  # worse than a loud one -- detect it explicitly and refuse to report a
  # claimable set with a diagnostic naming what failed, rather than relying
  # on the bare `set -e` trip.
  if ! held=$(held_prs); then
    echo "lease.sh: failed to read $NS lock state (gh api error) - refusing to report claimable PRs" >&2
    exit 1
  fi
  passed=$(passed_at)
  # The sibling of the guard above, and for a long time the ONLY unguarded
  # fetch in this function. `gh pr list` failing (auth/rate-limit/network)
  # under `set -e` killed claimable() the same silent way: exit 1, empty
  # stdout, EMPTY stderr -- and tools/reviewer/COORDINATOR.md step 3 reads an
  # empty claimable list as "queue empty, report and stop", so the live pool
  # went quiet with nothing anywhere saying why. Same discipline: capture the
  # status, fail closed, name the query that failed.
  if ! open=$(gh pr list --repo "$SLUG" --state open --limit 100 \
           --json number,isDraft,labels,headRefOid \
           -q '.[] | select(.isDraft | not)
                   | select([.labels[].name] | index("review-blocked") | not)
                   | select([.labels[].name] | index("hold") | not)
                   | "\(.number)\t\(.headRefOid)"'); then
    echo "lease.sh: failed to list open PRs (gh pr list error) - refusing to report claimable PRs" >&2
    exit 1
  fi
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
