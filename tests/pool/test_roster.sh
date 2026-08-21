#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
R=./tools/pool/roster.sh
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2' got '$3'"; fails=$((fails+1)); fi; }

check "lowest-tier implementer is antigravity" \
  "antigravity" "$($R implementers | head -1 | cut -f1)"
check "max-parallel counts implement rows" "2" "$($R max-parallel)"
check "a tier-1 PR can be reviewed by claude" \
  "claude" "$($R reviewers-above 1 | head -1 | cut -f1)"
check "a tier-2 PR can still be reviewed" \
  "claude" "$($R reviewers-above 2 | head -1 | cut -f1)"
check "a tier-3 PR has no eligible reviewer" \
  "" "$($R reviewers-above 3)"
check "comments are ignored" "" "$($R implementers | grep '^#' || true)"

[ "$fails" -eq 0 ] || exit 1
