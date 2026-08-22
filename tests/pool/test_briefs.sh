#!/usr/bin/env bash
# Runs `bash -n` over every fenced shell block in the agent briefs under
# tools/implementer/ and tools/reviewer/.
#
# WHAT THIS COVERS. Those briefs are pasted into unattended agents; dozens of
# commands live in them and, before this file, nothing had ever parsed a single
# one. A stray quote or an unbalanced `fi` in any of them would have surfaced at
# 2am, inside a worker, with no earlier signal. This catches that, cheaply.
#
# WHAT THIS DOES NOT COVER, stated plainly because the opposite has been
# claimed. `bash -n` is a SYNTAX check and nothing more. Neither of the two
# Important defects found in Task 7 was a syntax error:
#   - a budget guard that echoed a warning and then carried on instead of
#     exiting parses fine; the missing `exit` is valid bash.
#   - a lease deadline kept in a shell variable that agent shells do not carry
#     between tool calls parses fine; scope is not syntax.
# `bash -n` would have passed both, and so would this test. It would not have
# caught either finding. Do not read a green run here as "the briefs are
# correct" — it means only "the briefs are parseable".
#
# It also does not run anything. Blocks are parsed, never executed, which is
# why a brief full of `gh pr merge` is safe to lint.
set -uo pipefail
cd "$(dirname "$0")/../.."

fails=0
total_fences=0
total_shell=0

files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find tools/implementer tools/reviewer -maxdepth 1 -type f -name '*.md' | sort
)

# An extractor that silently matches nothing is this build's most repeated bug,
# and a brief-linter that lints nothing is that bug wearing a new hat. So every
# "found nothing" outcome below is a failure, never a quiet pass.
if [ "${#files[@]}" -eq 0 ]; then
  echo "FAIL - no *.md found under tools/implementer or tools/reviewer; there is nothing to lint, which is a failure, not a pass"
  exit 1
fi

# The briefs are templates: they say `issue-<n>`, `merge-gate.sh <PR>`. To bash
# that is a `<` redirect from a file called `n` followed by a stray `>`, so a
# literal parse reports a syntax error in every brief on lines that are working
# as designed. Angle-bracket placeholders are therefore flattened to a plain
# word before parsing. The cost, stated so it is not a surprise: a real
# redirection typo shaped exactly like `<word>` is flattened too and would not
# be reported. The pattern deliberately requires a letter straight after `<`,
# which is what keeps `< <(...)`, `<<'EOF'` and `2>&1` untouched.
PLACEHOLDER_RE='s/<[A-Za-z][A-Za-z0-9_.|-]*>/PLACEHOLDER/g'

# Does a bare ``` block's first content line look like shell? Conservative on
# purpose: an unrecognised block is skipped, and the fence-count cross-check
# below is what stops "skipped everything" from passing as "found nothing bad".
looks_like_shell() {
  case "$1" in
    '#!'*|'$ '*|'./'*|'tools/'*|'.superpowers/'*) return 0 ;;
    gh\ *|git\ *|orca\ *|bash\ *|sh\ *|set\ *|cd\ *|for\ *|while\ *|if\ *|case\ *) return 0 ;;
    echo\ *|printf\ *|export\ *|chmod\ *|mkdir\ *|cat\ *|sed\ *|awk\ *|grep\ *) return 0 ;;
    jq\ *|curl\ *|python3\ *|godot\ *|test\ *|'['\ *) return 0 ;;
    *) return 1 ;;
  esac
}

for f in "${files[@]}"; do
  fences=0 shell=0 in_block=0 lineno=0 start=0 info="" buf="" first=""
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    stripped="${line#"${line%%[![:space:]]*}"}"   # drop leading indentation
    case "$stripped" in
      '```'*)
        if [ "$in_block" -eq 0 ]; then
          in_block=1
          fences=$((fences + 1))
          start=$lineno
          info="${stripped#'```'}"
          buf=""
          first=""
        else
          in_block=0
          is_shell=0
          case "$info" in
            bash|sh|shell|bash\ *|sh\ *) is_shell=1 ;;
            '') if [ -n "$first" ] && looks_like_shell "$first"; then is_shell=1; fi ;;
          esac
          if [ "$is_shell" -eq 1 ]; then
            shell=$((shell + 1))
            if ! err=$(printf '%s' "$buf" | sed "$PLACEHOLDER_RE" | bash -n 2>&1); then
              echo "FAIL - $f: fenced block starting at line $start is not valid bash:"
              printf '%s\n' "$err" | sed 's/^/         /'
              fails=$((fails + 1))
            fi
          fi
        fi
        continue ;;
    esac
    if [ "$in_block" -eq 1 ]; then
      buf="$buf$line"$'\n'
      if [ -z "$first" ] && [ -n "$stripped" ]; then first="$stripped"; fi
    fi
  done < "$f"

  if [ "$in_block" -eq 1 ]; then
    echo "FAIL - $f: fenced block opened at line $start is never closed"
    fails=$((fails + 1))
  fi

  # Cross-check the parser against a dumb independent count. If the file
  # plainly has fences and the parser found none, the parser is broken and
  # every block in the file went unchecked — the exact silent-skip this test
  # is supposed to make impossible.
  raw=$(grep -c '^[[:space:]]*```' "$f" || true)
  if [ "$raw" -ge 2 ] && [ "$fences" -eq 0 ]; then
    echo "FAIL - $f: has $raw fence lines but the extractor found 0 blocks; the extractor is broken, not the file"
    fails=$((fails + 1))
  fi

  total_fences=$((total_fences + fences))
  total_shell=$((total_shell + shell))
  echo "ok   - $f: $fences fenced block(s), $shell shell block(s) parsed"
done

# --- The delivery contract, in BOTH coordinator briefs -----------------------
# `bash -n` cannot see this one, and it is the defect that actually happened:
# waiting with `check --wait --types ...` filters WAKE-UPS, not consumption, so
# a batch whose head is a heartbeat is never woken for, never consumed, and
# never acknowledged. That starved the reviewer pool for 630 s on run 18 while
# consecutive scheduled runs reported "no progress" on finished work. The fix
# was written into the implementer brief and never back-ported to the reviewer
# one, which is the LIVE pool -- so assert it on both, together, and keep them
# from drifting apart again.
#
# The literal string "check --wait --types" also appears in the WARNING both
# briefs carry ("Never write `check --wait --types ...`"), so the instruction
# is matched by its `orca orchestration` prefix, which the warning does not
# have.
for f in tools/implementer/COORDINATOR.md tools/reviewer/COORDINATOR.md; do
  if grep -q 'orchestration check --wait --types' "$f"; then
    echo "FAIL - $f: still instructs a type-filtered wait ('orca orchestration check --wait --types'); --types filters wake-ups, not consumption -- this is the 630s production deadlock"
    fails=$((fails + 1))
  else
    echo "ok   - $f: no type-filtered wait is instructed"
  fi

  if grep -q 'check --ack' "$f"; then
    echo "ok   - $f: acknowledges the delivery with 'check --ack'"
  else
    echo "FAIL - $f: never runs 'check --ack <deliveryId>'; an unacknowledged batch is replayed forever and the queue stops moving"
    fails=$((fails + 1))
  fi

  if grep -q 'what wakes a waiter' "$f"; then
    echo "ok   - $f: states that --types filters wake-ups, not consumption"
  else
    echo "FAIL - $f: does not state that --types selects only what wakes a waiter; without that a reader re-adds the filter"
    fails=$((fails + 1))
  fi
done

if [ "$total_shell" -eq 0 ]; then
  echo "FAIL - parsed 0 shell blocks across ${#files[@]} brief(s); a linter that lints nothing reports success while doing nothing"
  fails=$((fails + 1))
fi

echo "--- ${#files[@]} brief(s), $total_fences fenced block(s), $total_shell shell block(s) checked with bash -n"
[ "$fails" -eq 0 ] || exit 1
