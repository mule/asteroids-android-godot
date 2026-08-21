#!/usr/bin/env bash
# Unit tests for tools/implementer/deps.sh, pure and (mostly) offline.
#
# The dependency rule here is NOT "every #N under ## Dependencies" (that
# misreads "Blocks #54" as a requirement, and misreads a numberless
# "Requires every other issue" as zero requirements). It is: only the
# `Requires ...` clause, cut at the first period, counts — and if that
# clause names no issue number, the result is UNPARSEABLE (signalled by
# exit code 2), not "no dependencies" (exit 0, nothing printed). See
# tools/implementer/deps.sh's header comment for the full rationale.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=./tools/implementer/deps.sh
fails=0

check() { # check <label> <want-stdout> <got-stdout>
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2' got '$3'"; fails=$((fails+1)); fi
}

check_rc() { # check_rc <label> <want-rc> <got-rc>
  if [ "$2" = "$3" ]; then echo "ok   - $1 (rc=$2)"; else echo "FAIL - $1: want rc=$2 got rc=$3"; fails=$((fails+1)); fi
}

# --- Required table from the addendum -------------------------------------

out=$(printf '## Dependencies\n\nRequires #46. Blocks #54.\n' | $D); rc=$?
check "Requires clause only, trailing Blocks ignored" "46" "$out"
check_rc "  -> exit 0" 0 "$rc"

out=$(printf '## Dependencies\n\nRequires #44, #45. Completes the foundation; #48 onward can then proceed.\n' | $D); rc=$?
check "Requires clause only, trailing prose ignored" "44
45" "$out"
check_rc "  -> exit 0" 0 "$rc"

out=$(printf '## Dependencies\n\nNone on the sector work \xe2\x80\x94 in parallel with #48 and #49. Blocks #51.\n' | $D); rc=$?
check "no Requires clause -> dependency-free, not unparseable" "" "$out"
check_rc "  -> exit 0" 0 "$rc"

out=$(printf '## Dependencies\n\nRequires every other issue in the epic.\n' | $D); rc=$?
check "Requires clause with no issue number -> nothing on stdout" "" "$out"
check_rc "  -> UNPARSEABLE (exit 2)" 2 "$rc"

out=$(printf '## Dependencies\n\nRequires #44, #45.\n' | $D); rc=$?
check "simple two-dependency Requires clause" "44
45" "$out"
check_rc "  -> exit 0" 0 "$rc"

out=$(printf '## Goal\n\nDo a thing.\n' | $D); rc=$?
check "no ## Dependencies section at all" "" "$out"
check_rc "  -> exit 0" 0 "$rc"

out=$(printf 'Parent epic: #43\n\n## Goal\n\nSee #99.\n\n## Dependencies\n\nRequires #44.\n' | $D); rc=$?
check "issue refs outside the section are ignored" "44" "$out"
check_rc "  -> exit 0" 0 "$rc"

# --- Live-data assertions, pinning the parser to the real epic issues -----

out=$(gh issue view 47 --json body -q .body | $D | tr '\n' ' ' | xargs); rc=$?
check "real issue #47 needs 44 and 45" "44 45" "$out"
check_rc "  -> exit 0" 0 "$rc"

out=$(gh issue view 50 --json body -q .body | $D); rc=$?
check "real issue #50 has no dependencies" "" "$out"
check_rc "  -> exit 0, not unparseable" 0 "$rc"

out=$(gh issue view 53 --json body -q .body | $D); rc=$?
check "real issue #53 needs 46" "46" "$out"
check_rc "  -> exit 0" 0 "$rc"

out=$(gh issue view 59 --json body -q .body | $D); rc=$?
check "real issue #59 is UNPARSEABLE" "" "$out"
check_rc "  -> exit 2" 2 "$rc"

[ "$fails" -eq 0 ] || exit 1
