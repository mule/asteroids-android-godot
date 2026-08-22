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
G=./tools/reviewer/merge-gate.sh
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
check "the approved label does not override red checks" 1 \
  "$(gate "checks=fail labels=approved")"
check "the approved label does not override an absent check set" 2 \
  "$(gate "checks=none labels=approved")"

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
  *"--json author,changedFiles,additions,headRefOid,mergeStateStatus"*)
    printf '%s\n' "octo 3 42 $FAKE_HEAD $FAKE_MERGE_STATE" ;;
  *"--json statusCheckRollup"*) printf '%s\n' "$FAKE_ROLLUP" ;;
  *"--json reviews"*)           printf '%s\n' "$FAKE_APPROVALS" ;;
  *"--json labels"*)            printf '%s\n' "$FAKE_LABELS" ;;
  *"git/ref/reviewer-passed/pr-99"*) printf '%s\n' "$FAKE_PASSED"; exit "$FAKE_PASSED_RC" ;;
  *) printf 'stub: unexpected gh %s\n' "$args" >&2; exit 1 ;;
esac
GH
chmod +x "$STUB/gh"
export GH_CALLS="$STUB/calls" FAKE_HEAD="$HEAD"

live(){ # live <rollup> <labels> <passed-sha> <approvals> <merge_state> [passed-rc]
  : > "$GH_CALLS"
  export FAKE_ROLLUP="$1" FAKE_LABELS="$2" FAKE_PASSED="$3" \
         FAKE_APPROVALS="$4" FAKE_MERGE_STATE="$5" FAKE_PASSED_RC="${6:-0}"
  env -u GATE_FACTS PATH="$STUB:$PATH" $G 99 >/dev/null 2>"$STUB/err"
  echo $?
}

check "live: green checks + a review at head merges" 0 \
  "$(live '"SUCCESS"' 'review-passed' "$HEAD" 0 CLEAN)"
contains "live: it really called gh pr view" "gh pr view 99 --repo mule/asteroids-android-godot" \
  "$(cat "$GH_CALLS")"
contains "live: it really read the sha-pinned sign-off ref" "git/ref/reviewer-passed/pr-99" \
  "$(cat "$GH_CALLS")"
check "live: and it did NOT announce injected facts" "" \
  "$(grep -c INJECTED "$STUB/err" | grep -v '^0$' || true)"

check "live: the new hold rule applies to live data too" 1 \
  "$(live '"SUCCESS"' 'review-passed,hold' "$HEAD" 0 CLEAN)"
check "live: an empty rollup is checks=none and now waits" 2 \
  "$(live '' 'review-passed' "$HEAD" 0 CLEAN)"
check "live: a 404 on the sign-off ref is 'no review', not a sha" 2 \
  "$(live '"SUCCESS"' 'review-passed' '{"message":"Not Found"}' 0 CLEAN 1)"
check "live: an impl-tier:3 PR finds no eligible reviewer" 2 \
  "$(live '"SUCCESS"' 'review-passed,impl-tier:3' "$HEAD" 0 CLEAN)"

[ "$fails" -eq 0 ] || exit 1
