#!/usr/bin/env bash
# Regression tests for tools/implementer/ready.sh's failure-mode bugs found
# in fix round 1 by running the script under stubbed `gh` failures. Each
# stub is a fake `gh` placed first on PATH for a single invocation; calls
# it doesn't recognize fall through to the real `gh` binary.
set -uo pipefail
cd "$(dirname "$0")/../.."
READY=./tools/implementer/ready.sh
REALGH=$(command -v gh)
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2' got '$3'"; fails=$((fails+1)); fi; }

mkstub() { # mkstub <dir> <body-using-$REALGH> -- writes an executable gh stub
  mkdir -p "$1"
  {
    echo '#!/usr/bin/env bash'
    echo "REAL=\"$REALGH\""
    echo 'args="$*"'
    cat
  } > "$1/gh"
  chmod +x "$1/gh"
}

# --- Finding 1: a loop body whose last command is `[ ... ] && echo "$n"` ---
# leaks that test's own exit status as the whole pipeline's exit status.
# Construct the condition directly (don't rely on today's real issue
# states putting a ready issue last): two open epic issues, iterated in
# gh's list order 44 (free, ready) then 45 (blocked on an open #999) --
# i.e. the LAST issue processed is the blocked one.
STUB1=$(mktemp -d)
mkstub "$STUB1" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/implementer-locks/*)
    exit 0 ;;
  pr\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    exit 0 ;;
  issue\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    printf '44\t%s\n' "$(printf 'None.\n' | base64 -w0)"
    printf '45\t%s\n' "$(printf '## Dependencies\n\nRequires #999.\n' | base64 -w0)"
    ;;
  issue\ view\ 999\ --repo*)
    echo OPEN ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
out=$(PATH="$STUB1:$PATH" $READY); rc=$?
check "Finding 1: healthy run whose LAST-iterated issue is blocked prints the ready one" "44" "$out"
check "Finding 1:   ...and exits 0, not the blocked test's own non-zero status" 0 "$rc"
rm -rf "$STUB1"

# --- Finding 2: `gh pr list` itself failing must fail CLOSED -------------
# (auth/rate-limit/network), not be read as "no open PRs" and silently
# disable the open-PR exclusion.
STUB2=$(mktemp -d)
mkstub "$STUB2" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/implementer-locks/*)
    exit 0 ;;
  pr\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    exit 1 ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
out=$(PATH="$STUB2:$PATH" $READY 2>/dev/null); rc=$?
check "Finding 2: a failed 'gh pr list' prints nothing (fails closed)" "" "$out"
check "Finding 2:   ...and exits non-zero, not 0 with the exclusion silently disabled" 1 "$rc"
rm -rf "$STUB2"

# --- Finding 3, end to end: the lock-listing API call failing must also --
# fail CLOSED, not be read as "nothing is locked" (unit coverage for
# lock.sh's held() itself lives in tests/pool/test_lock.sh).
STUB3=$(mktemp -d)
mkstub "$STUB3" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/implementer-locks/*)
    exit 1 ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
out=$(PATH="$STUB3:$PATH" $READY 2>/dev/null); rc=$?
check "Finding 3: a failed lock-listing API call prints nothing (fails closed)" "" "$out"
check "Finding 3:   ...and exits non-zero, not 0 with every lock ignored" 1 "$rc"
rm -rf "$STUB3"


# --- Final review: the open-PR exclusion must match CLOSING references ----
# only, never a bare `#N` in prose. The old code grepped title+body for
# `#[0-9]+`, so ONE open PR saying "Closes #47. Does not change #50 or #53"
# excluded all three issues: a full ready set became empty output with rc=0,
# which the coordinator brief reads as "nothing ready" -- an idle epic and a
# starved queue are indistinguishable. This stub runs the REAL `-q` jq
# expression ready.sh sends against a real PR-list JSON document, so it
# exercises whatever fields the script actually asks for rather than a
# pre-rendered string that would agree with any query.
mkstub_prs() { # mkstub_prs <dir>  -- reads $PR_JSON from the environment
  mkstub "$1" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/implementer-locks/*)
    exit 0 ;;
  pr\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    q=""; prev=""
    for a in "$@"; do [ "$prev" = "-q" ] && q="$a"; prev="$a"; done
    if [ -z "$q" ]; then echo "stub: no -q given to gh pr list" >&2; exit 9; fi
    printf '%s' "$PR_JSON" | jq -r "$q" ;;
  issue\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    for n in 47 50 53; do
      printf '%s\t%s\n' "$n" "$(printf 'Parent epic: #43\n' | base64 -w0)"
    done ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
}

ready_with() { # ready_with <pr-list-json> -- prints ready.sh's stdout
  local d; d=$(mktemp -d)
  mkstub_prs "$d"
  PR_JSON="$1" PATH="$d:$PATH" $READY 2>/dev/null
  rm -rf "$d"
}

check "F1: a bare '#N' in prose does NOT exclude an issue" "47
50
53" \
  "$(ready_with '[{"title":"chore: tidy","body":"Related to #47 and #50.","closingIssuesReferences":[]}]')"

check "F1: the adversarial body excludes only the issue it CLOSES" "50
53" \
  "$(ready_with '[{"title":"chore: tidy","body":"Closes #47. Does not change #50 or #53","closingIssuesReferences":[{"number":47}]}]')"

check "F1: a genuine closing keyword still excludes its issue" "47
53" \
  "$(ready_with '[{"title":"feat: thing","body":"Fixes #50","closingIssuesReferences":[]}]')"

check "F1: every closing-keyword variant is honoured" "47" \
  "$(ready_with '[{"title":"a","body":"resolved #50"},{"title":"b","body":"FIXED: #53"}]')"

# The PR's own recorded link is the second source, and the only one that
# survives a PR whose body never spells the keyword out. A title alone is
# NOT a source: titles are prose too.
check "F1: a PR's recorded closingIssuesReferences excludes its issue" "47
50" \
  "$(ready_with '[{"title":"wip","body":"see the linked issue","closingIssuesReferences":[{"number":53}]}]')"

check "F1: a '#N' in the TITLE alone excludes nothing" "47
50
53" \
  "$(ready_with '[{"title":"follow-up to #47","body":"no closing keyword here","closingIssuesReferences":[]}]')"

[ "$fails" -eq 0 ] || exit 1
