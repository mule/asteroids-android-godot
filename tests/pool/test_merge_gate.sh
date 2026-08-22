#!/usr/bin/env bash
# Drives tools/reviewer/merge-gate.sh's decision table through its GATE_FACTS
# injection hook, so every policy arm is exercised without one real PR per arm.
#
# The gate is the only irreversible step in either pool, so the two properties
# this file exists to pin are:
#
#   1. every arm decides what the Task 8 addendum's table says it decides, and
#   2. GATE_FACTS changes NOTHING when it is unset. The last block below runs
#      the gate with GATE_FACTS unset against a stubbed `gh` and asserts it
#      really did go out to the live lookups (the stub records every call) and
#      really did not announce injected facts.
#
# A test that passes because the gate refused to run at all would be worse than
# no test, so the injected rows assert exit codes that differ across arms and
# the message-text rows assert what the operator actually reads on stderr.
set -uo pipefail
cd "$(dirname "$0")/../.."
# Overridable so a reviewer can point the suite at an older revision of the
# gate and watch the new rows fail. Defaults to the gate in the tree.
G="${GATE_UNDER_TEST:-./tools/reviewer/merge-gate.sh}"
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2' got '$3'"; fails=$((fails+1)); fi; }
contains(){ # contains <name> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok   - $1" ;;
    *) echo "FAIL - $1: '$2' not found in: $3"; fails=$((fails+1)) ;;
  esac
}

HEAD=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222

gate(){     GATE_FACTS="$1" $G 99 >/dev/null 2>&1; echo $?; }
gate_err(){ GATE_FACTS="$1" $G 99 2>&1 >/dev/null; }
# The verdict is the LAST stderr line: under GATE_FACTS the gate prints its
# injected-facts banner first, on purpose.
gate_verdict(){ gate_err "$1" | tail -1; }

# --- the emergency brake, which must outrank every other signal --------------
check "hold blocks an otherwise perfect PR" 1 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=hold")"
check "hold beats the approved label" 1 \
  "$(gate "checks=pass labels=approved,hold")"
check "hold beats a human APPROVED review" 1 \
  "$(gate "checks=pass approvals=1 labels=hold")"
contains "hold says how to release it" "remove the label" \
  "$(gate_err "checks=pass labels=hold")"
check "a label merely containing 'hold' is not the brake" 0 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=on-hold-maybe")"

# --- checks ------------------------------------------------------------------
check "red checks hold" 1 \
  "$(gate "checks=fail reviewed_sha=$HEAD head_sha=$HEAD")"
# The arm flipped by Task 8: an empty check set used to fall through to a merge.
check "absent checks await a green build" 2 \
  "$(gate "checks=none reviewed_sha=$HEAD head_sha=$HEAD")"
check "pending checks await a green build" 2 \
  "$(gate "checks=pending reviewed_sha=$HEAD head_sha=$HEAD")"
contains "absent checks say what is missing" "awaits a green build" \
  "$(gate_err "checks=none reviewed_sha=$HEAD head_sha=$HEAD")"
# The four approved/checks combinations. `approved` sits between the two check
# arms: it vouches for evidence that is MISSING, never for evidence that is red.
check "approved + fail is still a hold" 1 \
  "$(gate "checks=fail labels=approved")"
check "approved + none merges on the human's word" 0 \
  "$(gate "checks=none labels=approved")"
check "approved + pending merges on the human's word" 0 \
  "$(gate "checks=pending labels=approved")"
check "unapproved + none still awaits a green build" 2 \
  "$(gate "checks=none labels=review-passed")"
contains "the vouched-for merge says whose word it merged on" "vouched for by the approved label" \
  "$(gate_err "checks=none labels=approved")"

# `approved` was moved past the checks arm, NOT to the top of the table: the
# structural vetoes below it still hold an approved PR.
check "approved does not override review-blocked" 1 \
  "$(gate "checks=none labels=approved,review-blocked")"
check "approved does not override a conflicting base" 1 \
  "$(gate "checks=none merge_state=DIRTY labels=approved")"
check "hold still beats approved with no checks at all" 1 \
  "$(gate "checks=none labels=approved,hold")"

# --- the other pre-existing vetoes, unchanged --------------------------------
check "review-blocked holds" 1 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=review-blocked")"
check "a conflicting branch holds" 1 \
  "$(gate "checks=pass merge_state=DIRTY reviewed_sha=$HEAD head_sha=$HEAD")"
check "a branch behind base holds" 1 \
  "$(gate "checks=pass merge_state=BEHIND reviewed_sha=$HEAD head_sha=$HEAD")"

# --- the sha-pinned sign-off (PR #63/#65), unchanged -------------------------
check "no recorded review awaits review" 2 "$(gate "checks=pass")"
check "a review at a stale sha awaits a re-review" 2 \
  "$(gate "checks=pass reviewed_sha=$OLD head_sha=$HEAD")"
check "the stale-review message is unchanged" \
  "gate: reviewed at 2222222 but head is now 1111111 -> #99 needs a re-review" \
  "$(gate_verdict "checks=pass reviewed_sha=$OLD head_sha=$HEAD")"

# --- the tier invariant -------------------------------------------------------
# Shipped roster: implement tier 1 and 2, review tier 3. So `reviewers-above`
# answers for 1 and 2 and is empty for 3.
check "impl-tier:1 with green checks and a review at head merges" 0 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=impl-tier:1")"
check "impl-tier:2 still has a reviewer above it" 0 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=impl-tier:2")"
check "impl-tier:3 has nobody above it and awaits sign-off" 2 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=impl-tier:3")"
contains "the tier refusal names the tier" "no roster reviewer above impl-tier:3" \
  "$(gate_err "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=impl-tier:3")"
check "an absent impl-tier label defaults to tier 1" 0 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=review-passed")"
contains "the merge line records the tier it cleared" "tier>1" \
  "$(gate_err "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=review-passed")"
check "two tier labels are read as the higher one" 2 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=impl-tier:1,impl-tier:3")"
check "an unparseable impl-tier label holds rather than defaulting" 1 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=impl-tier:high")"
check "a human APPROVED review is not subject to the tier invariant" 0 \
  "$(gate "checks=pass approvals=1 reviewed_sha=$HEAD head_sha=$HEAD labels=impl-tier:3")"
check "the approved label is not subject to the tier invariant" 0 \
  "$(gate "checks=pass reviewed_sha=$HEAD head_sha=$HEAD labels=impl-tier:3,approved")"

# A roster we cannot read is not "no eligible reviewer" and it is certainly not
# "merge". Not knowing whether the invariant holds has to hold the PR.
gate_roster(){ GATE_FACTS="$2" POOL_ROSTER="$1" $G 99 >/dev/null 2>&1; echo $?; }
gate_roster_err(){ GATE_FACTS="$2" POOL_ROSTER="$1" $G 99 2>&1 >/dev/null; }
check "an unreadable roster holds instead of merging" 1 \
  "$(gate_roster /nonexistent/roster.tsv "checks=pass reviewed_sha=$HEAD head_sha=$HEAD")"
contains "and says the invariant could not be verified" "cannot verify the tier invariant" \
  "$(gate_roster_err /nonexistent/roster.tsv "checks=pass reviewed_sha=$HEAD head_sha=$HEAD")"

# --- GATE_FACTS unset: the gate must still read live data --------------------
# Everything above proves the decision table. None of it proves the pool's own
# code path still works, and a hook that quietly hijacked the unset case would
# pass every row above while merging on fiction. So: stub `gh`, run with
# GATE_FACTS explicitly removed from the environment, and assert both that the
# live lookups actually happened and that the injected-facts banner did not.
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/gh" <<'GH'
#!/usr/bin/env bash
args="$*"
printf '%s\n' "gh $args" >> "$GH_CALLS"
case "$args" in
  *"repo view --json nameWithOwner"*) printf '%s\n' "mule/asteroids-android-godot" ;;
  # Like the rollup query, this one can be made to FAIL while still writing to
  # stdout — which is what `gh` really does with an error body.
  *"--json author,changedFiles,additions,headRefOid,mergeStateStatus"*)
    printf '%s\n' "$FAKE_PRVIEW"; exit "$FAKE_PRVIEW_RC" ;;
  # One rollup query now. It can be made to FAIL while still writing to stdout,
  # which is what `gh` really does with an error body and is the whole point of
  # the fail-closed rows below.
  *"--json statusCheckRollup"*)
    printf '%s\n' "$FAKE_ROLLUP"; exit "$FAKE_ROLLUP_RC" ;;
  *"--json reviews"*) printf '%s\n' "$FAKE_APPROVALS" ;;
  *"--json labels"*)  printf '%s\n' "$FAKE_LABELS" ;;
  *"git/ref/reviewer-passed/pr-99"*) printf '%s\n' "$FAKE_PASSED"; exit "$FAKE_PASSED_RC" ;;
  *) printf 'stub: unexpected gh %s\n' "$args" >&2; exit 1 ;;
esac
GH
chmod +x "$STUB/gh"
export GH_CALLS="$STUB/calls" FAKE_HEAD="$HEAD"

live(){ # live <rollup> <labels> <passed-sha> <approvals> <merge_state> [passed-rc] [rollup-rc]
  # <rollup> is written as newline-separated `name=verdict` for readability and
  # converted to the tab-separated shape the gate's -q template emits. When
  # <rollup-rc> is non-zero it is passed through verbatim instead, because that
  # is the case where the text is an error body rather than a rollup.
  : > "$GH_CALLS"
  local rrc="${7:-0}" rollup
  if [ "$rrc" -ne 0 ] || [ -z "$1" ]; then
    rollup="$1"
  else
    rollup=$(printf '%s\n' "$1" | awk -F= '{printf "%s\t%s\n", $1, $2}')
  fi
  # LIVE_PRVIEW / LIVE_PRVIEW_RC let a caller break the pr-view query without
  # another positional argument. Unset, they render the ordinary answer, so
  # every existing row is untouched.
  export FAKE_ROLLUP="$rollup" FAKE_LABELS="$2" FAKE_PASSED="$3" \
         FAKE_APPROVALS="$4" FAKE_MERGE_STATE="$5" FAKE_PASSED_RC="${6:-0}" \
         FAKE_ROLLUP_RC="$rrc" \
         FAKE_PRVIEW="${LIVE_PRVIEW-octo 3 42 $HEAD $5}" \
         FAKE_PRVIEW_RC="${LIVE_PRVIEW_RC:-0}"
  env -u GATE_FACTS PATH="$STUB:$PATH" $G 99 >/dev/null 2>"$STUB/err"
  echo $?
}

check "live: green checks + a review at head merges" 0 \
  "$(live 'tests=SUCCESS' 'review-passed' "$HEAD" 0 CLEAN)"
contains "live: it really called gh pr view" "gh pr view 99 --repo mule/asteroids-android-godot" \
  "$(cat "$GH_CALLS")"
contains "live: it really read the sha-pinned sign-off ref" "git/ref/reviewer-passed/pr-99" \
  "$(cat "$GH_CALLS")"
check "live: and it did NOT announce injected facts" "" \
  "$(grep -c INJECTED "$STUB/err" | grep -v '^0$' || true)"

check "live: the hold rule applies to live data too" 1 \
  "$(live 'tests=SUCCESS' 'review-passed,hold' "$HEAD" 0 CLEAN)"
check "live: an empty rollup is checks=none and waits" 2 \
  "$(live '' 'review-passed' "$HEAD" 0 CLEAN)"
check "live: a 404 on the sign-off ref is 'no review', not a sha" 2 \
  "$(live 'tests=SUCCESS' 'review-passed' '{"message":"Not Found"}' 0 CLEAN 1)"
check "live: an impl-tier:3 PR finds no eligible reviewer" 2 \
  "$(live 'tests=SUCCESS' 'review-passed,impl-tier:3' "$HEAD" 0 CLEAN)"

# --- a FAILED rollup query is an error, never data ---------------------------
# `gh` writes its error body to stdout. Before this was fixed, that body was
# classified like a rollup, matched no failure or pending pattern, and fell
# through to checks=pass — the gate returned 0 and MERGED on an auth expiry, a
# rate limit or a transient 5xx. Non-empty output is not evidence of success.
check "live: a failed rollup query holds instead of merging" 1 \
  "$(live '{"message":"Bad credentials","status":"401"}' 'review-passed' "$HEAD" 0 CLEAN 0 1)"
contains "live: and it names the call that failed" "statusCheckRollup' failed" \
  "$(cat "$STUB/err")"
check "live: a failed rollup query is not rescued by approved either" 1 \
  "$(live '{"message":"API rate limit exceeded"}' 'approved' "$HEAD" 0 CLEAN 0 1)"
# An error body that happens to contain the word FAILURE must still be refused
# as an error, not classified as a red build that merely looks the same.
check "live: an error body mentioning FAILURE is still an error" 1 \
  "$(live '{"message":"FAILURE contacting api.github.com"}' 'review-passed' "$HEAD" 0 CLEAN 0 1)"

# --- the $CI_JOB check must be named, not inferred from a green rollup -------
check "live: a green rollup WITHOUT a tests entry must not merge" 2 \
  "$(live 'lint=SUCCESS' 'review-passed' "$HEAD" 0 CLEAN)"
contains "live: and it says the evidence is missing, not that it passed" "checks=none" \
  "$(cat "$STUB/err")"
check "live: a green rollup WITH a tests entry merges" 0 \
  "$(live 'lint=SUCCESS
tests=SUCCESS' 'review-passed' "$HEAD" 0 CLEAN)"
# A check merely NAMED like a verdict must not be read as one.
check "live: a check named failure-injection is not a failing build" 0 \
  "$(live 'failure-injection=SUCCESS
tests=SUCCESS' 'review-passed' "$HEAD" 0 CLEAN)"

# --- every conclusion value this gate classifies -----------------------------
# Terminal negative conclusions are a verdict of red -> "fail" -> exit 1.
# Everything else that is not SUCCESS is the ABSENCE of a verdict: an empty
# conclusion is an in-flight run -> "pending", and SKIPPED / CANCELLED /
# NEUTRAL / STALE -> "none". Both are exit 2: they block the merge, self-heal
# on a re-run, and stay rescuable by `approved`. Routing them to exit 1 would
# make the reviewer stamp the sticky review-blocked label on routine activity.
tests_row(){ live "tests=$1" 'review-passed' "$HEAD" 0 CLEAN; }
check "conclusion SUCCESS         -> merge"   0 "$(tests_row SUCCESS)"
check "conclusion FAILURE         -> hold"    1 "$(tests_row FAILURE)"
check "conclusion TIMED_OUT       -> hold"    1 "$(tests_row TIMED_OUT)"
check "conclusion ACTION_REQUIRED -> hold"    1 "$(tests_row ACTION_REQUIRED)"
check "conclusion STARTUP_FAILURE -> hold"    1 "$(tests_row STARTUP_FAILURE)"
check "conclusion ERROR           -> hold"    1 "$(tests_row ERROR)"
check "conclusion SKIPPED         -> wait"    2 "$(tests_row SKIPPED)"
check "conclusion CANCELLED       -> wait"    2 "$(tests_row CANCELLED)"
check "conclusion NEUTRAL         -> wait"    2 "$(tests_row NEUTRAL)"
check "conclusion STALE           -> wait"    2 "$(tests_row STALE)"
check "conclusion <empty>         -> wait"    2 "$(tests_row '')"
check "conclusion IN_PROGRESS     -> wait"    2 "$(tests_row IN_PROGRESS)"
check "an unrecognised conclusion is absence, not a pass" 2 "$(tests_row WHAT_IS_THIS)"

contains "an in-flight tests row reads as pending, not failed" "checks=pending" \
  "$(tests_row '' >/dev/null; cat "$STUB/err")"
contains "a cancelled tests row reads as none, not failed" "checks=none" \
  "$(tests_row CANCELLED >/dev/null; cat "$STUB/err")"

# Worst verdict wins across duplicate rows: a re-run can leave two.
check "one green and one red tests row is not green" 1 \
  "$(live 'tests=SUCCESS
tests=FAILURE' 'review-passed' "$HEAD" 0 CLEAN)"
check "one green and one cancelled tests row is not green" 2 \
  "$(live 'tests=SUCCESS
tests=CANCELLED' 'review-passed' "$HEAD" 0 CLEAN)"

# Absence is rescuable by a human; a terminal negative is not.
check "approved rescues a rollup with no tests entry" 0 \
  "$(live 'lint=SUCCESS' 'approved' "" 0 CLEAN)"
check "approved rescues a CANCELLED tests job" 0 \
  "$(live 'tests=CANCELLED' 'approved' "" 0 CLEAN)"
check "approved rescues an in-flight tests job" 0 \
  "$(live 'tests=' 'approved' "" 0 CLEAN)"
check "approved does not rescue a red tests job" 1 \
  "$(live 'tests=FAILURE' 'approved' "" 0 CLEAN)"

# --- the job name is not a guess ---------------------------------------------
# The gate hardcodes one check name. Nothing in git ties it to the workflow, and
# renaming that job would silently turn every PR into checks=none — this build
# already shipped one bug of exactly this shape (a lease-comment marker string
# two files had to agree on, and didn't). So read the name out of the gate and
# assert the job really exists, rather than restating "tests" here and moving
# the coupling one file over.
CI_JOB=$(awk '/^CI_JOB=/{sub(/^CI_JOB=/,""); print $1; exit}' tools/reviewer/merge-gate.sh)
check "the gate declares the CI job it requires" "yes" \
  "$([ -n "$CI_JOB" ] && echo yes || echo no)"
check "that job id exists in .github/workflows/ci.yml" "yes" \
  "$(grep -qE "^[[:space:]]{2}${CI_JOB}:[[:space:]]*$" .github/workflows/ci.yml && echo yes || echo no)"
check "and the workflow runs on pull_request, or the check never appears" "yes" \
  "$(grep -qE '^[[:space:]]+pull_request:' .github/workflows/ci.yml && echo yes || echo no)"
check "the job does not override its name (which would change the check name)" "yes" \
  "$(awk -v j="$CI_JOB" '
       $0 ~ "^  " j ":" {inj=1; next}
       inj && /^  [A-Za-z0-9_-]+:/ {inj=0}
       inj && /^    name:/ {found=1}
       END {print (found ? "no" : "yes")}' .github/workflows/ci.yml)"

# --- the sibling fail-open: the pr-view query -------------------------------
# `read -r ... <<<"$(gh pr view ...)"` threw the call's exit status away. `gh`
# writes its error body to stdout, so `read` split that body across the five
# variables: $head_sha and $merge_state came out empty, the DIRTY|BEHIND
# conflict guard matched nothing, and an `approved` PR merged at rc=0 onto a
# base it conflicts with. Same family as the rollup hole, one call over.
pv_fail(){ # pv_fail <labels> [merge_state]
  LIVE_PRVIEW_RC=1 LIVE_PRVIEW='{"message":"Bad credentials","status":"401"}' \
    live 'tests=SUCCESS' "$1" "$HEAD" 0 "${2:-DIRTY}"
}
check "live: a failed pr-view query holds even with approved" 1 "$(pv_fail approved)"
check "live: a failed pr-view query holds without approved too" 1 "$(pv_fail review-passed)"
contains "live: and it names the query that failed" "author,changedFiles,additions,headRefOid,mergeStateStatus" \
  "$(cat "$STUB/err")"
check "live: an empty pr-view response holds" 1 \
  "$(LIVE_PRVIEW='' live 'tests=SUCCESS' 'approved' "$HEAD" 0 CLEAN)"
# A zero exit is not proof the answer is usable: `null` fields parse fine and
# bypass the conflict guard exactly as an outright failure did.
check "live: a null head sha holds" 1 \
  "$(LIVE_PRVIEW="octo 3 42 null CLEAN" live 'tests=SUCCESS' 'approved' "$HEAD" 0 CLEAN)"
check "live: a null merge state holds" 1 \
  "$(LIVE_PRVIEW="octo 3 42 $HEAD " live 'tests=SUCCESS' 'approved' "$HEAD" 0 CLEAN)"
# Controls: the query working must still decide exactly as before.
check "live: pr-view working, approved + clean base still merges" 0 \
  "$(live 'tests=SUCCESS' 'approved' "" 0 CLEAN)"
check "live: pr-view working, the conflict guard still fires" 1 \
  "$(live 'tests=SUCCESS' 'approved' "" 0 DIRTY)"
check "live: pr-view working, a review at head still merges" 0 \
  "$(live 'tests=SUCCESS' 'review-passed' "$HEAD" 0 CLEAN)"

[ "$fails" -eq 0 ] || exit 1
