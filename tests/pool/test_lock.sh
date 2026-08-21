#!/usr/bin/env bash
# Integration test against real GitHub: ref creation is the mutex, so a
# fake would test nothing. Uses a throwaway namespace and cleans up.
set -uo pipefail
cd "$(dirname "$0")/../.."
L=./tools/pool/lock.sh
NS=selftest-locks
KEY=probe-1
SHA=$(gh api repos/mule/asteroids-android-godot/git/ref/heads/main -q .object.sha)
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want $2 got $3"; fails=$((fails+1)); fi; }

$L release "$NS" "$KEY" >/dev/null 2>&1

$L claim "$NS" "$KEY" "$SHA" >/dev/null 2>&1; check "first claim wins" 0 $?
$L claim "$NS" "$KEY" "$SHA" >/dev/null 2>&1; check "second claim loses" 1 $?
check "held lists the key" "$KEY" "$($L held "$NS")"

$L gc "$NS" "some-other-key" >/dev/null 2>&1
check "gc drops keys not live" "" "$($L held "$NS")"

$L claim "$NS" "$KEY" "$SHA" >/dev/null 2>&1
$L release "$NS" "$KEY" >/dev/null 2>&1
check "release frees the key" "" "$($L held "$NS")"

# sha on a ref that was never claimed must be empty, not the raw 404 body
# gh api leaves on stdout (regression test for the "missing ref reads as
# present" bug).
check "sha on a missing ref is empty" "" "$($L sha "$NS" never-claimed-key 2>/dev/null)"

# stamp's <n> is derived from a key's suffix and is not always a real
# issue/PR number. A bad one must not abort the script (it used to, via a
# raw failing `gh api` under set -e) and must not leak the 404 body as if
# it were a timestamp.
$L stamp not-a-real-issue-id >/dev/null 2>&1; check "stamp on a bad id doesn't abort" 0 $?
check "stamp on a bad id is empty" "" "$($L stamp not-a-real-issue-id 2>/dev/null)"

# sweep must process every held key even when the first one it looks at
# can't be stamped -- with the un-fixed stamp(), this died on the first key
# and never reached the second.
$L claim "$NS" "badstamp-xyz" "$SHA" >/dev/null 2>&1
$L claim "$NS" "probe-2" "$SHA" >/dev/null 2>&1
$L sweep "$NS" 999999 >/dev/null 2>&1; check "sweep completes past an unstampable key" 0 $?
check "sweep left both keys alone (ttl not exceeded)" "badstamp-xyz
probe-2" "$($L held "$NS")"
$L release "$NS" "badstamp-xyz" >/dev/null 2>&1
$L release "$NS" "probe-2" >/dev/null 2>&1

# unknown subcommand: a clear error, not a silent no-op.
$L bogus-subcommand >/dev/null 2>&1; check "unknown subcommand exits 2" 2 $?

# held() must distinguish "the namespace genuinely holds nothing" (exit 0,
# nothing printed) from "the gh api call itself failed" (non-zero exit).
# Regression test for a bug where a trailing `|| true` on the whole
# `gh api ... | sed ...` pipeline made a failed API call look exactly like
# an empty namespace to every caller, including tools/implementer/ready.sh
# -- an outage would then read as "nothing is locked" and let two agents
# claim the same issue.
check "held on a genuinely empty namespace exits 0" 0 "$($L held selftest-locks-truly-empty-ns >/dev/null 2>&1; echo $?)"

STUBDIR=$(mktemp -d)
REALGH=$(command -v gh)
cat > "$STUBDIR/gh" <<STUBEOF
#!/usr/bin/env bash
case "\$*" in
  *git/matching-refs*) exit 1 ;;
  *) exec "$REALGH" "\$@" ;;
esac
STUBEOF
chmod +x "$STUBDIR/gh"
PATH="$STUBDIR:$PATH" $L held "$NS" >/dev/null 2>&1
check "held propagates a failed gh api call as non-zero, not empty" 1 $?
rm -rf "$STUBDIR"

[ "$fails" -eq 0 ] || exit 1
