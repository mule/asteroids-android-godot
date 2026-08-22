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
#   $checks         "pass" | "fail" | "pending" | "none". Stricter than "the
#                   rollup is not red": "pass" additionally requires a check
#                   named $CI_JOB to be present and SUCCESS, so a rollup of
#                   unrelated green checks is "none", not "pass". "fail" is
#                   reserved for terminal negative conclusions; SKIPPED,
#                   CANCELLED, NEUTRAL and STALE are absence of a verdict and
#                   read as "none", an empty conclusion reads as "pending".
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

# The one check whose verdict this gate treats as "CI". It is the job id in
# .github/workflows/ci.yml, and because that job carries no `name:` it is also
# the check-run name GitHub reports (PR #67's rollup reads `tests:SUCCESS`).
#
# Nothing in git ties this string to that file, and renaming the job would
# silently turn every PR into checks=none. tests/pool/test_merge_gate.sh reads
# this line and asserts the job id still exists in the workflow, so the two
# cannot drift apart unnoticed. Keep it a plain literal assignment on one line:
# that test parses it.
CI_JOB=tests

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
  # Which repo are we even deciding about. As a `${VAR:-$(...)}` default this
  # aborted the whole script under `set -e` with no output at all when `gh`
  # failed -- fail-closed, but an operator sees a pool that stopped merging and
  # nothing saying why, which is only marginally better than one that continues
  # wrongly. Same discipline as the two calls below: status first, then shape.
  if [ -n "${REVIEW_REPO:-}" ]; then
    SLUG="$REVIEW_REPO"
  else
    SLUG=""
    slug_rc=0
    SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner) || slug_rc=$?
    if [ "$slug_rc" -ne 0 ]; then
      echo "gate: 'gh repo view --json nameWithOwner' failed (exit $slug_rc) -> hold #$pr; cannot tell which repo to evaluate" >&2
      exit 1
    fi
    case "$SLUG" in
      */*) ;;
      *) echo "gate: 'gh repo view --json nameWithOwner' gave '$SLUG' -> hold #$pr; that is not an owner/repo slug" >&2
         exit 1 ;;
    esac
  fi

  # The namespace tools/reviewer/lease.sh's `mark-passed` writes into, via the
  # shared lock primitive in tools/pool/lock.sh (its `sha` subcommand owns the
  # actual ref path — no hand-copied ref format here to drift out of sync).
  NS_PASSED=reviewer-passed
  export POOL_REPO="$SLUG"

  # The PR's own facts. This is the sibling of the rollup call below and it had
  # the same fail-open: `read <<<"$(gh ...)"` throws the exit status away, and
  # since `gh` writes its error body to STDOUT, `read` happily split
  # `{"message":"Bad credentials",...}` across the five variables. $head_sha and
  # $merge_state came out empty, the DIRTY|BEHIND conflict guard then matched
  # nothing, and an `approved` PR merged at rc=0 onto a base it conflicts with.
  # Narrower than the rollup hole -- it needs a human label -- but identical in
  # kind, so it gets identical treatment: capture the status, and on non-zero
  # refuse without parsing the output at all.
  pr_facts=""
  pr_facts_rc=0
  pr_facts=$(gh pr view "$pr" --repo "$SLUG" \
    --json author,changedFiles,additions,headRefOid,mergeStateStatus \
    -q '"\(.author.login) \(.changedFiles) \(.additions) \(.headRefOid) \(.mergeStateStatus)"') \
    || pr_facts_rc=$?
  if [ "$pr_facts_rc" -ne 0 ]; then
    echo "gate: 'gh pr view --json author,changedFiles,additions,headRefOid,mergeStateStatus' failed for #$pr (exit $pr_facts_rc) -> hold; its output is an error body, not a PR state, and unknown is not mergeable" >&2
    exit 1
  fi
  if [ -z "$pr_facts" ]; then
    echo "gate: 'gh pr view --json author,changedFiles,additions,headRefOid,mergeStateStatus' returned nothing for #$pr -> hold; the PR's head sha and merge state are unknown" >&2
    exit 1
  fi
  read -r author changed_files additions head_sha merge_state <<<"$pr_facts"

  # A zero exit is not proof the answer is usable. If the template renders
  # `null` for a field GitHub could not resolve, the line parses fine and the
  # conflict guard is bypassed exactly as it was on an outright failure -- the
  # same hole, one door over. A head that is not a sha, or an empty merge
  # state, means this PR's state is unknown.
  if ! grep -qE '^[0-9a-f]{40}$' <<<"$head_sha" || [ -z "$merge_state" ]; then
    echo "gate: 'gh pr view' gave head='$head_sha' mergeStateStatus='$merge_state' for #$pr -> hold; that is not a usable PR state" >&2
    exit 1
  fi

  # ONE rollup query serving both classifiers below, because they read the same
  # object and one call means one exit status to get right.
  #
  # A FAILED QUERY IS AN ERROR, NEVER DATA. `gh` writes its error body to
  # STDOUT, so a failed call produces output that reads like a rollup. The
  # previous `2>/dev/null || echo ""` fed that body straight into the
  # classifier, where `{"message":"Bad credentials"}` matched neither the
  # failure nor the pending patterns and fell through to checks="pass" — an
  # auth expiry, a rate limit or a transient 5xx made this gate return 0 and
  # MERGE. So: capture the exit status, and on non-zero refuse without
  # inspecting the output at all. Non-empty output is not evidence of success.
  #
  # This refuses with exit 1 rather than exit 2 because a failed API call is
  # not "clean but unsigned", it is "the gate could not evaluate". gh's own
  # stderr is deliberately left unsuppressed so the operator sees the cause.
  rollup=""
  rollup_rc=0
  rollup=$(gh pr view "$pr" --repo "$SLUG" --json statusCheckRollup \
    -q '.statusCheckRollup[]? | "\(.name // .context)\t\(.conclusion // .state // "")"') \
    || rollup_rc=$?
  if [ "$rollup_rc" -ne 0 ]; then
    echo "gate: 'gh pr view --json statusCheckRollup' failed for #$pr (exit $rollup_rc) -> hold; the check status is unknown, and unknown is not green" >&2
    exit 1
  fi

  # Verdicts are read from the second column only. Matching the whole line
  # would let a check NAMED "failure-injection" read as a failing build.
  #
  # Three groups, and the line between them is the same one the `approved`
  # label is built on — a terminal negative conclusion is a verdict of red, and
  # everything else is the absence of one:
  #   terminal negative -> "fail" (exit 1, a human is needed). ERROR is kept
  #     from the pre-existing set (it is the StatusContext spelling) even though
  #     the round-2 ruling did not enumerate it; dropping it would quietly
  #     weaken the gate.
  #   still running     -> "pending" (exit 2). An empty conclusion is the shape
  #     of an in-flight check run, so it belongs here, not in "fail".
  #   SKIPPED, CANCELLED, NEUTRAL, STALE and anything unrecognised -> handled
  #     below as absence, never as red. Cancelled runs are routine (a
  #     superseding push, a concurrency group); calling them red would exit 1,
  #     which makes the reviewer stamp the sticky `review-blocked` label on
  #     ordinary activity and teaches an operator to strip the one label that
  #     means a human owes an answer.
  rollup_fail=0
  rollup_pending=0
  tests_seen=0
  tests_fail=0
  tests_pending=0
  tests_inconclusive=0
  while IFS=$'\t' read -r c_name c_verdict; do
    [ -n "$c_name" ] || continue
    case "$c_verdict" in
      FAILURE|ERROR|TIMED_OUT|ACTION_REQUIRED|STARTUP_FAILURE) rollup_fail=1 ;;
      PENDING|IN_PROGRESS|QUEUED|WAITING|REQUESTED|'')         rollup_pending=1 ;;
    esac
    [ "$c_name" = "$CI_JOB" ] || continue
    tests_seen=1
    case "$c_verdict" in
      SUCCESS)                                                 ;;
      FAILURE|ERROR|TIMED_OUT|ACTION_REQUIRED|STARTUP_FAILURE) tests_fail=1 ;;
      PENDING|IN_PROGRESS|QUEUED|WAITING|REQUESTED|'')         tests_pending=1 ;;
      *)                                                       tests_inconclusive=1 ;;
    esac
  done <<<"$rollup"

  if   [ -z "$rollup" ];             then checks="none"
  elif [ "$rollup_fail" -eq 1 ];     then checks="fail"
  elif [ "$rollup_pending" -eq 1 ];  then checks="pending"
  else                                    checks="pass"; fi

  # "Nothing red and nothing running" is not the same question as "did this
  # repo's suite run and go green". A PR carrying one unrelated successful
  # check and no `$CI_JOB` row at all produced checks=pass and merged, on a
  # build that never happened. The whole autonomy argument is "green CI plus a
  # higher-tier review", so the gate has to name the check it means.
  #
  # Worst verdict wins across duplicate rows: a re-run can leave two.
  # This can only ever downgrade `pass`, never promote anything to it.
  if [ "$checks" = "pass" ]; then
    if   [ "$tests_seen" -eq 0 ];         then checks="none"
    elif [ "$tests_fail" -eq 1 ];         then checks="fail"
    elif [ "$tests_pending" -eq 1 ];      then checks="pending"
    elif [ "$tests_inconclusive" -eq 1 ]; then checks="none"
    fi
  fi

  # Human APPROVED reviews. A bare assignment aborted under `set -e` with no
  # diagnostic; and had it not aborted, an error body in $approvals would have
  # blown up the later `[ "$approvals" -ge 1 ]` instead. Capture the status,
  # then insist the answer is actually a count.
  approvals=""
  approvals_rc=0
  approvals=$(gh pr view "$pr" --repo "$SLUG" --json reviews \
    -q '[.reviews[] | select(.state=="APPROVED")] | length') || approvals_rc=$?
  if [ "$approvals_rc" -ne 0 ]; then
    echo "gate: 'gh pr view --json reviews' failed for #$pr (exit $approvals_rc) -> hold; the human approval count is unknown" >&2
    exit 1
  fi
  case "$approvals" in
    ''|*[!0-9]*)
      echo "gate: 'gh pr view --json reviews' gave approvals='$approvals' for #$pr -> hold; that is not a count" >&2
      exit 1 ;;
  esac

  # The labels, and this is the one that matters most: every has_label call
  # below reads this string, so an empty $labels is indistinguishable from a PR
  # that genuinely carries no labels -- which would silently disarm `hold`, the
  # operator's emergency brake, and `review-blocked`. Measured, the bare
  # assignment did abort under `set -e` rather than continue (rc=1), so this was
  # fail-closed, not fail-open; but it aborted with EMPTY stderr, so the brake
  # looked identical to a merge gate that had simply crashed. An empty answer is
  # NOT rejected here: a PR with no labels is ordinary and legitimate. Only a
  # failed call is.
  labels=""
  labels_rc=0
  labels=$(gh pr view "$pr" --repo "$SLUG" --json labels -q '[.labels[].name] | join(",")') || labels_rc=$?
  if [ "$labels_rc" -ne 0 ]; then
    echo "gate: 'gh pr view --json labels' failed for #$pr (exit $labels_rc) -> hold; the label state is unknown, so neither hold nor review-blocked can be trusted to be absent" >&2
    exit 1
  fi

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
# MERGE. tools/reviewer/lease.sh's claimable() now excludes `hold` as well, so
# a held PR is no longer claimed, reviewed, commented on or pushed to either —
# the brake stops the work and the merge. These two filters are the same rule
# in two places: if one ever learns a new stop-label, so must the other.
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
