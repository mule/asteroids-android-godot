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

[ "$fails" -eq 0 ] || exit 1
