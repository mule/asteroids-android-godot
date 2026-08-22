#!/usr/bin/env bash
# Regression test for tools/reviewer/lease.sh's claimable(), found in fix
# round 2 of the implementer-readiness task: lock.sh's held() (fixed in
# round 1 to return non-zero on a genuine `gh api` failure, rather than
# reading it as "namespace empty") has a caller here that used to feed it
# straight into a plain assignment. Under `set -e` + `pipefail`, a failing
# `held_prs()` silently killed claimable() -- exit 1, no stderr, no partial
# output -- which matters because lease.sh is the LIVE reviewer pool's
# claim path on an enabled 30-minute automation: an operator would see a
# coordinator that stopped claiming with nothing explaining why.
set -uo pipefail
cd "$(dirname "$0")/../.."
LEASE=./tools/reviewer/lease.sh
REALGH=$(command -v gh)
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2' got '$3'"; fails=$((fails+1)); fi; }

mkstub() { # mkstub <dir> -- writes an executable gh stub from stdin
  mkdir -p "$1"
  {
    echo '#!/usr/bin/env bash'
    echo "REAL=\"$REALGH\""
    echo 'args="$*"'
    cat
  } > "$1/gh"
  chmod +x "$1/gh"
}

# A failing `gh api .../reviewer-locks/` call (the same shape as fix round
# 1's Finding 3, one namespace over) must make claimable() fail closed
# EXPLICITLY: non-zero exit, a diagnostic on stderr naming what failed, and
# no PR numbers on stdout -- not a bare, silent `set -e` death.
STUB=$(mktemp -d)
mkstub "$STUB" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/reviewer-locks/*)
    exit 1 ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF

errfile=$(mktemp)
out=$(PATH="$STUB:$PATH" $LEASE claimable 2>"$errfile")
rc=$?
err=$(cat "$errfile")
rm -f "$errfile"
rm -rf "$STUB"

check "claimable() exits non-zero on a failed locks-API call" 1 "$rc"
check "claimable() prints no PR numbers to stdout" "" "$out"
if [ -n "$err" ]; then echo "ok   - claimable() prints a diagnostic to stderr: $err"; else echo "FAIL - claimable() printed nothing to stderr"; fails=$((fails+1)); fi


contains(){ case "$3" in *"$2"*) echo "ok   - $1" ;; *) echo "FAIL - $1: '$2' not found in: $3"; fails=$((fails+1)) ;; esac; }
lacks(){ case "$3" in *"$2"*) echo "FAIL - $1: '$2' should NOT appear in: $3"; fails=$((fails+1)) ;; *) echo "ok   - $1" ;; esac; }

# --- F2: the OTHER fetch in claimable() ---------------------------------
# `held_prs` was guarded in fix round 2; the `gh pr list` five lines later
# was not. Forced to exit 1 it produced rc=1, empty stdout and EMPTY
# stderr, and tools/reviewer/COORDINATOR.md step 3 reads an empty claimable
# list as "queue empty, report and stop" -- the live pool goes quiet with no
# diagnostic anywhere. The exit code alone cannot tell those two apart, so
# the load-bearing assertion here is the stderr one.
STUB2=$(mktemp -d)
mkstub "$STUB2" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/reviewer-*)
    exit 0 ;;
  pr\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    exit 1 ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
errfile=$(mktemp)
out=$(PATH="$STUB2:$PATH" $LEASE claimable 2>"$errfile"); rc=$?
err=$(cat "$errfile"); rm -f "$errfile"; rm -rf "$STUB2"
check "F2: a failed 'gh pr list' exits non-zero" 1 "$rc"
check "F2:   ...and prints no PR numbers" "" "$out"
contains "F2:   ...and names the query that failed on stderr" "gh pr list" "$err"

# --- F4: `hold` is the operator's brake, so it must stop the CLAIM too ---
# The gate honours `hold` as its first rule, but claimable() filtered only
# review-blocked and drafts: a held PR was still claimed, reviewed,
# commented on and pushed to, and only bounced at the very end. The stub
# runs the REAL `-q` jq expression lease.sh sends, against a real PR-list
# document, so the filter itself is what is under test.
STUB4=$(mktemp -d)
mkstub "$STUB4" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/reviewer-*)
    exit 0 ;;
  pr\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    q=""; prev=""
    for a in "$@"; do [ "$prev" = "-q" ] && q="$a"; prev="$a"; done
    if [ -z "$q" ]; then echo "stub: no -q given to gh pr list" >&2; exit 9; fi
    printf '%s' "$PR_JSON" | jq -r "$q" ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
PR_JSON='[{"number":88,"isDraft":false,"labels":[{"name":"hold"}],"headRefOid":"aaa"},
          {"number":89,"isDraft":false,"labels":[],"headRefOid":"bbb"},
          {"number":90,"isDraft":false,"labels":[{"name":"review-blocked"}],"headRefOid":"ccc"},
          {"number":91,"isDraft":true,"labels":[],"headRefOid":"ddd"}]'
out=$(PR_JSON="$PR_JSON" PATH="$STUB4:$PATH" $LEASE claimable 2>/dev/null); rc=$?
rm -rf "$STUB4"
check "F4: a 'hold' PR is not claimable (drafts/review-blocked still excluded)" "89" "$out"
check "F4:   ...and claimable() still exits 0" 0 "$rc"

# --- F5: mark-passed enforces the tier invariant mechanically -----------
# REVIEWER.md step 3 has the reviewer push fixes on nearly every PR and step
# 5 asks it to remember to stamp its own impl-tier first, so "forgot to
# stamp" was the DEFAULT path and a tier-3 reviewer cleared its own commits
# under the implementer's tier-1 label. `claim` already pinned the head sha
# in refs/reviewer-locks/pr-N, so mark-passed can detect those pushed
# commits with no authorship lookup at all.
mkstub_pass() { # mkstub_pass <dir> -- driven by env: HEAD_SHA CLAIMED_SHA PR_LABELS GH_CALLS LBL_STATE
  mkstub "$1" <<'STUBEOF'
echo "$args" >> "$GH_CALLS"
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/pulls/77\ -q\ .head.sha)
    echo "$HEAD_SHA" ;;
  api\ repos/mule/asteroids-android-godot/git/ref/reviewer-locks/pr-77\ -q\ .object.sha)
    if [ -z "$CLAIMED_SHA" ]; then echo '{"message":"Not Found"}'; exit 1; fi
    echo "$CLAIMED_SHA" ;;
  api\ -X\ DELETE\ *)
    exit 0 ;;
  api\ repos/mule/asteroids-android-godot/git/refs\ *)
    echo '{}' ;;
  pr\ view\ 77\ *--json\ labels*)
    for l in $PR_LABELS; do echo "$l"; done
    if [ -f "$LBL_STATE" ]; then cat "$LBL_STATE"; fi
    exit 0 ;;
  pr\ edit\ 77\ *--add-label\ impl-tier:*)
    echo "${args##*--add-label }" >> "$LBL_STATE"; exit 0 ;;
  pr\ edit\ 77\ *)
    exit 0 ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
}

MP_RC=0; MP_DIR=""; MP_CALLS=""; MP_ERRTXT=""
run_mark_passed() { # run_mark_passed <claimed-sha> <pr-labels> [roster-file]
  MP_DIR=$(mktemp -d)
  : > "$MP_DIR/calls"; : > "$MP_DIR/labels"
  mkstub_pass "$MP_DIR"
  env GH_CALLS="$MP_DIR/calls" LBL_STATE="$MP_DIR/labels" \
      HEAD_SHA=headsha222 CLAIMED_SHA="$1" PR_LABELS="$2" \
      ${3:+POOL_ROSTER="$3"} \
      PATH="$MP_DIR:$PATH" $LEASE mark-passed 77 >/dev/null 2>"$MP_DIR/err"
  MP_RC=$?
  MP_CALLS=$(cat "$MP_DIR/calls")
  MP_ERRTXT=$(cat "$MP_DIR/err")
  rm -rf "$MP_DIR"
}

# 1. Head unchanged since the lease was claimed -> nothing was pushed, so no
#    label is touched and the pass is recorded exactly as before.
run_mark_passed headsha222 "impl-tier:1"
check "F5: an unchanged head records the pass" 0 "$MP_RC"
contains "F5:   ...pinning the passed ref at the head sha" \
  "git/refs -f ref=refs/reviewer-passed/pr-77 -f sha=headsha222" "$MP_CALLS"
lacks "F5:   ...and touches no impl-tier label" "--add-label impl-tier" "$MP_CALLS"

# 2. Head MOVED under the lease -> the reviewer pushed commits, so its own
#    roster tier is stamped before the pass is recorded, and the lower
#    impl-tier label the implementer left is removed.
run_mark_passed implsha111 "impl-tier:1"
check "F5: a moved head still records the pass" 0 "$MP_RC"
contains "F5:   ...after auto-stamping the roster's review tier" \
  "pr edit 77 --repo mule/asteroids-android-godot --add-label impl-tier:3" "$MP_CALLS"
contains "F5:   ...removing the stale lower tier" "--remove-label impl-tier:1" "$MP_CALLS"
contains "F5:   ...and saying so on stderr" "the reviewer pushed commits" "$MP_ERRTXT"

# 3. The stamped tier comes from the ROSTER, not from a literal in the script.
ROSTER7=$(mktemp)
printf 'implement\tantigravity\t3.7-flash\t-\t1\nreview\tclaude\topus\tmax\t7\n' > "$ROSTER7"
run_mark_passed implsha111 "" "$ROSTER7"
check "F5: an edited roster changes the stamped tier (not hardcoded)" 0 "$MP_RC"
contains "F5:   ...to the roster's own review tier" "--add-label impl-tier:7" "$MP_CALLS"
rm -f "$ROSTER7"

# 4. No lease ref at all -> the comparison is impossible, so "the head did
#    not move" would be a guess. Refuse, and record nothing.
run_mark_passed "" "impl-tier:1"
check "F5: no recorded lease -> mark-passed refuses" 1 "$MP_RC"
lacks "F5:   ...and records no pass" "ref=refs/reviewer-passed/pr-77" "$MP_CALLS"
contains "F5:   ...and says why" "no reviewer-locks lease recorded" "$MP_ERRTXT"

# 5. A label edit that FAILS must not still record a pass -- reporting
#    success while having done nothing is the defect class this branch is
#    entirely about.
STUB5=$(mktemp -d)
: > "$STUB5/calls"
mkstub "$STUB5" <<'STUBEOF'
echo "$args" >> "$GH_CALLS"
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/pulls/77\ -q\ .head.sha)
    echo headsha222 ;;
  api\ repos/mule/asteroids-android-godot/git/ref/reviewer-locks/pr-77\ -q\ .object.sha)
    echo implsha111 ;;
  pr\ view\ 77\ *--json\ labels*)
    exit 0 ;;
  pr\ edit\ 77\ *--add-label\ impl-tier:*)
    exit 1 ;;
  pr\ edit\ 77\ *|api\ *)
    exit 0 ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
env GH_CALLS="$STUB5/calls" PATH="$STUB5:$PATH" $LEASE mark-passed 77 \
  >/dev/null 2>"$STUB5/err"
rc=$?
calls=$(cat "$STUB5/calls"); err=$(cat "$STUB5/err"); rm -rf "$STUB5"
check "F5: a failed impl-tier edit refuses the pass" 1 "$rc"
lacks "F5:   ...and records no pass" "ref=refs/reviewer-passed/pr-77" "$calls"
contains "F5:   ...and says the edit failed" "cannot add impl-tier" "$err"

[ "$fails" -eq 0 ] || exit 1
