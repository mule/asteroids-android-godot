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

[ "$fails" -eq 0 ] || exit 1
