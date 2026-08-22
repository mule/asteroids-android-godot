#!/usr/bin/env bash
# Regression test for precheck.sh Finding 1 (fix round 1): the pre-fix
# version discarded ready.sh's own exit status via `[ -n "$("$READY")" ]`,
# so "genuinely idle" and "gh outage, can't tell" were indistinguishable at
# the exit-code level -- both gave rc=1. Confirmed (fix round 1) to FAIL
# against the pre-fix committed precheck.sh: the third case below wanted
# rc=2 and got rc=1, identical to the idle case. See task-6-report.md.
#
# Each stub is a fake `gh` placed first on PATH for one invocation, same
# technique as tests/pool/test_ready.sh; calls it doesn't recognize fall
# through to the real `gh` binary.
set -uo pipefail
cd "$(dirname "$0")/../.."
PRECHECK=./tools/implementer/precheck.sh
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

# --- Case A: ready.sh succeeds and prints a ready issue -> precheck runs -
STUBA=$(mktemp -d)
mkstub "$STUBA" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/implementer-locks/*)
    exit 0 ;;
  pr\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    exit 0 ;;
  issue\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    printf '100\t%s\n' "$(printf 'None.\n' | base64 -w0)" ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
PATH="$STUBA:$PATH" "$PRECHECK" >/dev/null 2>/dev/null; rc=$?
check "ready.sh succeeds with work -> precheck runs (rc=0)" 0 "$rc"
rm -rf "$STUBA"

# --- Case B: ready.sh succeeds, genuinely idle -> precheck skips, rc=1 --
STUBB=$(mktemp -d)
mkstub "$STUBB" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/implementer-locks/*)
    exit 0 ;;
  pr\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    exit 0 ;;
  issue\ list\ --repo\ mule/asteroids-android-godot\ --state\ open*)
    ;;  # empty: no open epic issues at all
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
PATH="$STUBB:$PATH" "$PRECHECK" >/dev/null 2>/dev/null; rc=$?
check "ready.sh succeeds but idle -> precheck skips (rc=1)" 1 "$rc"
rm -rf "$STUBB"

# --- Case C: ready.sh itself FAILS (gh api error) -> precheck skips, rc=2,
# and this must be distinguishable from Case B at the exit-code level --
# that distinction is exactly the bug this test guards against.
STUBC=$(mktemp -d)
mkstub "$STUBC" <<'STUBEOF'
case "$args" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "mule/asteroids-android-godot" ;;
  api\ repos/mule/asteroids-android-godot/git/matching-refs/implementer-locks/*)
    exit 1 ;;
  *)
    exec "$REAL" "$@" ;;
esac
STUBEOF
errfile=$(mktemp)
PATH="$STUBC:$PATH" "$PRECHECK" >/dev/null 2>"$errfile"; rc=$?
check "ready.sh FAILS -> precheck skips (rc=2), distinct from idle" 2 "$rc"
if grep -q "ready.sh" "$errfile"; then diag=found; else diag=missing; fi
check "  ...and says so on stderr" "found" "$diag"
rm -rf "$STUBC" "$errfile"

[ "$fails" -eq 0 ] || exit 1
