#!/usr/bin/env bash
# Decides whether a reviewed PR may be merged by the bot.
#
# This is the one irreversible step in the whole loop, so it is deliberately
# a separate, readable file rather than prose buried in an agent prompt.
# The reviewer agent MUST call this and honour its exit code:
#   exit 0 -> merge
#   exit 1 -> hold: something is wrong, label review-blocked, a human must look
#   exit 2 -> not cleared at this sha: it belongs in the review queue, not here
#
# Facts available to you (all already fetched below):
#   $pr             PR number
#   $checks         "pass" | "fail" | "pending" | "none". "pass" is stricter
#                   than "the rollup is not red": it additionally requires the
#                   `tests` check (the job in .github/workflows/ci.yml) to be
#                   present and SUCCESS. A rollup of unrelated green checks
#                   with no `tests` entry is "none", not "pass".
#   $approvals      number of human APPROVED reviews
#   $reviewed_sha   head sha a reviewer cleared, "" if it never cleared one
#   $head_sha       head sha the PR is at right now
#   $merge_state    GitHub's mergeStateStatus (CLEAN, DIRTY, BLOCKED, ...)
#   $labels         comma-separated label names
#   $impl_tier      roster tier that built the PR, from its impl-tier:<n>
#                   label; 1 when the label is absent
#   $changed_files  number of files touched
#   $additions      lines added
#   $author         PR author login
#
# TESTING HOOK. If GATE_FACTS is set and non-empty it must be a space-separated
# list of key=value tokens (the names above without the `$`, plus `impl_tier`).
# Those values replace every live lookup and NO `gh` call is made, which is the
# only way tests/pool/test_merge_gate.sh can exercise every policy arm without
# one real PR per arm. Values may not contain spaces. When GATE_FACTS is unset
# -- the only way the pool itself ever runs this -- not one line of the live
# path below is skipped and the decision is identical to what it was before the
# hook existed. When it IS set the gate says so on stderr first, because a
# decision made on injected facts must never be read off a log as a decision
# made about the real PR.
set -euo pipefail
pr="$1"

# Anchored to this script's own location, not cwd — a bare relative path
# would break the moment this ran from somewhere other than the repo root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK="$SCRIPT_DIR/../pool/lock.sh"
ROSTER="$SCRIPT_DIR/../pool/roster.sh"

# Set only by the GATE_FACTS branch; empty everywhere else means "derive it
# from the labels", which is what the live path wants.
impl_tier=""

if [ -n "${GATE_FACTS:-}" ]; then
  echo "gate: GATE_FACTS is set -> deciding #$pr on INJECTED facts, not on live data" >&2

  # The expansion of $GATE_FACTS is deliberately unquoted: it is a
  # space-separated token list and the word splitting *is* the parse. No
  # pipeline and no subshell here on purpose — a `sed`/`head` pipe for a key
  # that simply is not present is exactly the shape `pipefail` turns into a
  # silent abort.
  fact() { # fact <key> <default>
    local kv
    for kv in ${GATE_FACTS}; do
      case "$kv" in "$1"=*) printf '%s' "${kv#"$1"=}"; return 0 ;; esac
    done
    printf '%s' "$2"
  }
  checks=$(fact checks none)
  labels=$(fact labels "")
  approvals=$(fact approvals 0)
  reviewed_sha=$(fact reviewed_sha "")
  head_sha=$(fact head_sha 0000000000000000000000000000000000000000)
  merge_state=$(fact merge_state CLEAN)
  impl_tier=$(fact impl_tier "")
  author=$(fact author gate-facts)
  changed_files=$(fact changed_files 0)
  additions=$(fact additions 0)
else
  SLUG="${REVIEW_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

  # The namespace tools/reviewer/lease.sh's `mark-passed` writes into, via the
  # shared lock primitive in tools/pool/lock.sh (its `sha` subcommand owns the
  # actual ref path — no hand-copied ref format here to drift out of sync).
  NS_PASSED=reviewer-passed
  export POOL_REPO="$SLUG"

  read -r author changed_files additions head_sha merge_state <<<"$(gh pr view "$pr" --repo "$SLUG" \
    --json author,changedFiles,additions,headRefOid,mergeStateStatus \
    -q '"\(.author.login) \(.changedFiles) \(.additions) \(.headRefOid) \(.mergeStateStatus)"')"

  rollup=$(gh pr view "$pr" --repo "$SLUG" --json statusCheckRollup \
    -q '[.statusCheckRollup[]?.conclusion // .statusCheckRollup[]?.state] | @csv' 2>/dev/null || echo "")
  if   [ -z "$rollup" ];                       then checks="none"
  elif grep -qiE 'FAILURE|ERROR|TIMED_OUT'     <<<"$rollup"; then checks="fail"
  elif grep -qiE 'PENDING|IN_PROGRESS|QUEUED'  <<<"$rollup"; then checks="pending"
  else                                              checks="pass"; fi

  # The rollup above answers "is anything red or still running", which is not
  # the same question as "did this repo's suite run and go green". A PR that
  # carries one unrelated successful check and no `tests` entry at all produced
  # checks=pass and merged — on a build that never happened. The whole autonomy
  # argument is "green CI plus a higher-tier review", so the gate has to name
  # the check it means.
  #
  # `tests` is the job id in .github/workflows/ci.yml, and with no `name:` on
  # that job it is also the check-run name GitHub reports here (PR #67's rollup
  # reads `tests:SUCCESS`).
  #
  # Second call rather than reworking the first: the two answers are different
  # questions and this one must fail differently. `|| rollup_named=""` REPLACES
  # the value instead of appending to it, because `gh` writes error bodies to
  # stdout — a `|| echo ""` here would launder an error JSON into the check
  # names and could match nothing while looking like a clean read.
  rollup_named=$(gh pr view "$pr" --repo "$SLUG" --json statusCheckRollup \
    -q '.statusCheckRollup[]? | "\(.name // .context)=\(.conclusion // .state // "")"') \
    || rollup_named=""

  # Every entry, not just the first: a re-run can leave two rows with this name
  # and any non-SUCCESS among them means the suite is not green.
  tests_seen=0
  tests_green=1
  while IFS= read -r entry; do
    case "$entry" in
      tests=*)
        tests_seen=1
        case "${entry#tests=}" in SUCCESS|success) ;; *) tests_green=0 ;; esac ;;
    esac
  done <<<"$rollup_named"

  # An additional requirement, never a relaxation: this can only downgrade
  # `pass`, never promote anything to it.
  #   tests absent    -> "none". Absence of evidence, so it lands on the exit-2
  #                      arm and a human's `approved` can still vouch for it.
  #   tests not green -> "fail". Present and not SUCCESS is negative evidence,
  #                      including SKIPPED and CANCELLED: a suite that did not
  #                      finish is not a suite that passed, and no label gets
  #                      to wave that through.
  if [ "$checks" = "pass" ]; then
    if [ "$tests_seen" -eq 0 ]; then
      checks="none"
    elif [ "$tests_green" -eq 0 ]; then
      checks="fail"
    fi
  fi

  approvals=$(gh pr view "$pr" --repo "$SLUG" --json reviews \
    -q '[.reviews[] | select(.state=="APPROVED")] | length')

  labels=$(gh pr view "$pr" --repo "$SLUG" --json labels -q '[.labels[].name] | join(",")')

  # The sign-off: a reviewer agent recorded a clean review at one exact head sha
  # via `lease.sh mark-passed`. Pinning to the sha is the whole point. The
  # `review-passed` label survives a later push; this ref does not, so a PR that
  # grows new commits after its review stops clearing the gate and falls back
  # into the claimable queue instead of merging on a stale label.
  reviewed_sha=$("$LOCK" sha "$NS_PASSED" "pr-$pr")

  # A missing ref does not answer with an empty string: gh writes the 404 body to
  # stdout, `-q` does not filter an error response, and `|| echo ""` appends to it
  # rather than replacing it. Left alone, $reviewed_sha becomes
  # `{"message":"Not Found",...}` and the gate reports "reviewed at {"messa".
  # It still refuses to merge, since that can never equal a head sha, but it
  # refuses for a reason it cannot explain. Anything that is not a sha is "no
  # review recorded", which is what a 404 actually means.
  grep -qE '^[0-9a-f]{40}$' <<<"$reviewed_sha" || reviewed_sha=""
fi

has_label() { grep -qE "(^|,)$1(,|\$)" <<<"$labels"; }

# The tier that built this PR, read off its impl-tier:<n> label.
#   absent  -> 1. Unlabelled work is tier 1 by documented default.
#   several -> the HIGHEST. Two tier labels are two claims about who wrote the
#              code; the higher one demands the stronger reviewer, so it is the
#              only safe reading of a PR that makes both.
#   garbage -> refuse, below. `impl-tier:high` is not tier 1, and quietly
#              calling it tier 1 would hand the weakest reviewer on the roster
#              a PR nobody can vouch for.
tier_from_labels() {
  local l n best=1 IFS=,
  for l in $labels; do
    case "$l" in
      impl-tier:*)
        n=${l#impl-tier:}
        case "$n" in
          ''|*[!0-9]*)
            echo "gate: label '$l' is not impl-tier:<number> -> hold #$pr; fix the label, do not guess a tier" >&2
            return 1 ;;
        esac
        if [ "$n" -gt "$best" ]; then best=$n; fi ;;
    esac
  done
  printf '%s' "$best"
}

if [ -z "$impl_tier" ]; then
  impl_tier=$(tier_from_labels) || exit 1
fi
case "$impl_tier" in
  ''|*[!0-9]*)
    echo "gate: impl_tier='$impl_tier' is not a number -> hold #$pr; the tier invariant cannot be evaluated" >&2
    exit 1 ;;
esac

# Does the roster offer anyone allowed to clear tier-$impl_tier work?
#   0 -> yes, at least one row of a strictly greater tier
#   1 -> no, nobody outranks the builder
# A roster.sh that fails outright is neither answer: not knowing whether the
# invariant holds is not permission to merge, so that arm exits 1 on the spot
# rather than returning a value a caller could read as "ineligible, carry on".
tier_ok() {
  local eligible
  if ! eligible=$("$ROSTER" reviewers-above "$impl_tier"); then
    echo "gate: roster.sh reviewers-above $impl_tier failed -> hold #$pr; cannot verify the tier invariant" >&2
    exit 1
  fi
  [ -n "$eligible" ]
}

# --- merge policy -----------------------------------------------------------
# A clean agent review of the current head is the gate. Everything else below
# is a guard against merging something demonstrably broken on top of it.

# The operator's emergency brake, and deliberately the FIRST decision: `hold`
# outranks every other signal, including the `approved` label and a human
# APPROVED review. A brake that another label can override is not a brake.
#
# Its scope, stated accurately so the next reader is not misled: this stops the
# MERGE and only the merge. tools/reviewer/lease.sh's claimable() filters
# `review-blocked` and drafts, not `hold`, so a held PR is still claimed,
# reviewed, commented on and pushed to — the pool keeps working on it, it just
# never lands. Whether claimable() should honour `hold` too is an open design
# question and is deliberately not answered here.
if has_label hold; then
  echo "gate: hold label -> hold #$pr; an operator stopped this one, remove the label to release it" >&2
  exit 1
fi

# A red build vetoes outright, and NO label overrides it. `approved` is checked
# below this, never above it.
if [ "$checks" = "fail" ]; then
  echo "gate: checks=fail -> hold #$pr" >&2
  exit 1
fi

# `approved` sits BETWEEN the two check arms. That looks like an odd place to
# put it and a later reader will want to tidy it upward or downward; both are
# wrong, so here is the reasoning.
#
# The distinction the gate is drawing is absence of evidence versus presence of
# negative evidence. `checks=none` and `checks=pending` are absence: nothing has
# reported, so the automation cannot decide, and deciding is exactly what a
# human sign-off is for. `checks=fail` is negative evidence: something reported,
# and it reported red. A human may vouch for a signal that is missing. A human
# may not wave through a signal that is actively saying no — that is not an
# escape hatch, that is overriding the test suite by label.
#
# Move `approved` ABOVE the fail arm and a label merges a demonstrably red
# build. Move it BELOW the not-pass arm and the fast path stops working
# precisely when CI is absent or broken, which is when an escape hatch is for.
# It belongs here, between them.
#
# This arm only lets execution continue. `approved` still has to reach the
# sign-off chain below, so review-blocked and a conflicting base still hold an
# approved PR exactly as they did before.
if [ "$checks" != "pass" ]; then
  if has_label approved; then
    echo "gate: checks=$checks, vouched for by the approved label -> #$pr proceeds" >&2
  else
    echo "gate: checks=$checks -> #$pr awaits a green build" >&2
    exit 2
  fi
fi

# review-blocked means a human still owes an answer. `lease.sh mergeable`
# already filters these out, but this is the irreversible step, so it re-checks
# rather than trusting its caller to have done it.
if has_label review-blocked; then
  echo "gate: review-blocked -> hold #$pr" >&2
  exit 1
fi

# A PR that no longer merges cleanly is not a merge decision, it is a
# reconciliation decision: someone has to choose whose version of the
# conflicting code survives, and that choice is not reviewed work.
case "$merge_state" in
  DIRTY|BEHIND)
    echo "gate: mergeStateStatus=$merge_state -> #$pr conflicts with the base, needs a rebase and a fresh review" >&2
    exit 1 ;;
esac

# The actual policy: a reviewer agent cleared *this* sha. A human APPROVED
# review or the `approved` label still clear the gate too, so a person can
# always sign off on something the pool would not pass by itself.
agent_cleared=no
if [ -n "$reviewed_sha" ] && [ "$reviewed_sha" = "$head_sha" ]; then agent_cleared=yes; fi

# The tier invariant guards the agent arm, and only the agent arm. An agent may
# never clear work built at its own tier or below — that is self-approval with
# extra steps, and it is exactly what happens when a reviewer fixes findings
# itself on an unlabelled PR (hence the stamping rule in REVIEWER.md). The two
# human arms below are deliberately not subject to it: a person signing off in
# their own name is what autonomy degrades *to*, not a roster row to outrank.
if [ "$agent_cleared" = yes ] && tier_ok; then
  signoff="agent-review@${head_sha:0:7} tier>$impl_tier"
elif [ "$approvals" -ge 1 ]; then
  signoff="human-approval"
elif has_label approved; then
  signoff="approved-label"
elif [ "$agent_cleared" = yes ]; then
  echo "gate: no roster reviewer above impl-tier:$impl_tier -> #$pr awaits sign-off from a human or a higher tier" >&2
  exit 2
elif [ -n "$reviewed_sha" ]; then
  echo "gate: reviewed at ${reviewed_sha:0:7} but head is now ${head_sha:0:7} -> #$pr needs a re-review" >&2
  exit 2
else
  echo "gate: no clean review recorded -> #$pr awaits review" >&2
  exit 2
fi

echo "gate: checks=$checks signoff=$signoff -> merge #$pr" >&2
exit 0
