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

# Every agent the roster names must be one Orca can actually launch. Orca's
# `worker-start --agent` validates against its *installed* agents, not against
# whatever binary happens to be on PATH, and rejects anything else with
# `agent_unconfigured`. Such a row burns a claim every scheduled run: the
# coordinator locks the issue, worker-start fails, and the issue is handed back
# untouched -- and since max-parallel counts rows, it also inflates the fleet
# budget past what can start.
#
# THE SOURCE OF TRUTH IS `orca agent hooks status`, which prints every agent id
# Orca knows and marks each `installed` or `not_installed`. Only `installed`
# ids may appear below. That two-state split is the whole trap, so do not skip
# the command and reason from a directory listing:
#
#   * `cursor` is a *known* id that is `not_installed` here. It reads as
#     plausible -- Orca's own `worker-start` note says "--model supports
#     Claude, Codex, and Cursor" -- but that sentence is about which providers
#     accept a pinned MODEL id, an entirely different axis from whether the
#     agent can be launched at all. Conflating them is what put `cursor` in
#     this list originally.
#   * `opencode` is not in the enumeration at all, so the tempting repair of
#     the original `opencode-go` typo -- rename it to the binary that IS on
#     PATH -- fails identically. `~/.config/orca/opencode-hooks/` exists, but
#     it holds a status-line plugin for the opencode TUI, not an agent
#     registration.
#
# Hardcoded rather than derived because CI has no Orca to ask. Re-run the
# command and update this line when the host's agent set changes.
LAUNCHABLE=" antigravity claude codex "

# Both roles, not just `implement`: roster.tsv promises this of *every* agent
# it names, and a review row that cannot launch fails the same way. Tiers are
# >= 1, so `reviewers-above 0` is every review row.
for a in $( { $R implementers; $R reviewers-above 0; } | cut -f1 | sort -u ); do
  case "$LAUNCHABLE" in
    *" $a "*) got="$a" ;;
    *)        got="$a (not 'installed' per: orca agent hooks status)" ;;
  esac
  check "roster agent '$a' is one Orca can launch" "$a" "$got"
done

[ "$fails" -eq 0 ] || exit 1
