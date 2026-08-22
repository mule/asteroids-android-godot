#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
R=./tools/pool/roster.sh
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2' got '$3'"; fails=$((fails+1)); fi; }

check "lowest-tier implementer is antigravity" \
  "antigravity" "$($R implementers | head -1 | cut -f1)"
check "max-parallel counts implement rows" "3" "$($R max-parallel)"
check "a tier-1 PR can be reviewed by claude" \
  "claude" "$($R reviewers-above 1 | head -1 | cut -f1)"
check "a tier-2 PR can still be reviewed" \
  "claude" "$($R reviewers-above 2 | head -1 | cut -f1)"
check "a tier-3 PR has no eligible reviewer" \
  "" "$($R reviewers-above 3)"
check "comments are ignored" "" "$($R implementers | grep '^#' || true)"

# Every implementer must be an agent id Orca can actually launch. Orca's
# `worker-start --agent` validates against its *configured* agents, not against
# whatever binary happens to be on PATH, and rejects an unknown id with
# `agent_unconfigured`. A roster row naming an unconfigured agent burns a claim
# every scheduled run: the coordinator locks the issue, worker-start fails, and
# the issue is handed back untouched. Keep this list in step with the agents
# configured in Orca (see ~/.orca/agent-hooks/).
LAUNCHABLE=" antigravity claude codex cursor "
for a in $($R implementers | cut -f1); do
  case "$LAUNCHABLE" in
    *" $a "*) check "implementer '$a' is a launchable Orca agent" "$a" "$a" ;;
    *) check "implementer '$a' is a launchable Orca agent" "<one of:$LAUNCHABLE>" "$a" ;;
  esac
done

[ "$fails" -eq 0 ] || exit 1
