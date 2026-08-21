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

[ "$fails" -eq 0 ] || exit 1
