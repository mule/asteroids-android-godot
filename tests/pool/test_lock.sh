#!/usr/bin/env bash
# Integration test against real GitHub: ref creation is the mutex, so a
# fake would test nothing. Every namespace this suite touches is derived
# from a per-run id, so two runs in flight at once (a CI run overlapping a
# local run, two pushes in quick succession, or two local runs started at
# once) never collide on the same ref: $GITHUB_RUN_ID differs across CI
# runs, and $$ plus a clock reading differs across local processes even
# started in the same second. A trap releases everything this run created,
# even if an assertion fails partway through, so the namespace never
# accumulates litter under a name nobody can trace back to a run.
set -uo pipefail
cd "$(dirname "$0")/../.."
L=./tools/pool/lock.sh
REPO=mule/asteroids-android-godot
RUN_ID="${GITHUB_RUN_ID:-$$-$(date +%s%N)}"
NS="selftest-locks-$RUN_ID"
EMPTY_NS="selftest-locks-empty-$RUN_ID"
KEY=probe-1
SHA=$(gh api "repos/$REPO/git/ref/heads/main" -q .object.sha)
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want $2 got $3"; fails=$((fails+1)); fi; }

STUBDIR=""
cleanup() {
  $L gc "$NS" >/dev/null 2>&1 || true
  $L gc "$EMPTY_NS" >/dev/null 2>&1 || true
  [ -n "$STUBDIR" ] && rm -rf "$STUBDIR" 2>/dev/null
  return 0
}
trap cleanup EXIT

# Probe write access before anything else, by attempting the exact write
# every check below depends on: creating a throwaway ref in THIS RUN's own
# unique namespace. Detecting this by probing -- not by sniffing $CI or
# $GITHUB_ACTIONS -- means a developer machine whose token quietly lost
# write scope fails loudly here too, instead of an environment-sniffing
# skip hiding the exact case you most want to fail loudly.
#
# Only a clean HTTP 403 (gh's own "(HTTP nnn)" suffix on a failed request)
# may turn this into a skip. Anything else -- network trouble, an expired
# token, a 404 on the repo, a 500, a response this suite can't parse -- is
# a real failure: skipping on an error the suite can't positively identify
# as "permission denied" is exactly how a broken suite ends up reporting
# green.
probe_err=$(gh api "repos/$REPO/git/refs" -f ref="refs/$NS/__write-probe" -f sha="$SHA" 2>&1 1>/dev/null)
probe_rc=$?
if [ "$probe_rc" -eq 0 ]; then
  $L release "$NS" "__write-probe" >/dev/null 2>&1 || true
elif printf '%s' "$probe_err" | grep -q '(HTTP 403)'; then
  {
    echo "SKIP (exit 77): this token cannot write git refs in $REPO."
    echo "  Attempted: create refs/$NS/__write-probe (POST git/refs)."
    echo "  Result:    denied with HTTP 403."
    echo "  tools/pool/lock.sh's compare-and-swap -- the actual mutex under"
    echo "  test -- was NOT exercised in this environment. This is a skip,"
    echo "  not a pass: none of the checks below ran."
  } >&2
  exit 77
else
  {
    echo "FAIL: could not verify write access to $REPO's git refs, and the"
    echo "  failure was not a clean HTTP 403 -- refusing to treat an"
    echo "  unrecognised error as a permission-denied skip."
    echo "  Attempted: create refs/$NS/__write-probe (POST git/refs)."
    echo "  gh said: $probe_err"
  } >&2
  exit 1
fi

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
check "held on a genuinely empty namespace exits 0" 0 "$($L held "$EMPTY_NS" >/dev/null 2>&1; echo $?)"

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
STUBDIR=""

[ "$fails" -eq 0 ] || exit 1
