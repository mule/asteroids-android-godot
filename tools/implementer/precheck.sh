#!/usr/bin/env bash
# Orca automation precheck. Exit codes are deliberately three-way, not just
# zero/non-zero, so a human (or a log scraper) can tell a quiet epic from a
# broken one even though Orca itself only branches on zero vs non-zero:
#   0 - ready.sh found at least one claimable issue -> run
#   1 - ready.sh ran fine and found nothing -> skip, genuinely idle
#   2 - ready.sh itself FAILED (e.g. a `gh` API error) -> skip, but say so
#       loudly on stderr; this must never read the same as "idle" (1),
#       because a persistent `gh` outage collapsing into rc=1 would look
#       identical to a healthy quiet epic and stall the pool silently.
# Skipped runs are cheap and recorded, so an idle epic costs no agent
# sessions -- this must be safe to run on every scheduler tick.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK="$SCRIPT_DIR/../pool/lock.sh"
READY="$SCRIPT_DIR/ready.sh"

# Stale-lock cleanup is maintenance, not the readiness decision itself --
# swallow its failure so a `gh` hiccup here can't block the actual gate
# below, which is ready.sh's own job to answer, and which fails closed on
# its own account.
"$LOCK" sweep implementer-locks 90 >/dev/null 2>&1 || true

# Capture ready.sh's stdout AND its exit status separately -- collapsing
# them (e.g. `[ -n "$("$READY")" ]`) discards the exit status entirely, so
# "ran fine, nothing ready" and "failed outright" both read as empty
# stdout and are indistinguishable to any caller that only checks rc
# zero-vs-non-zero at a coarser level than this script's own exit code.
ready_rc=0
issues="$("$READY")" || ready_rc=$?

if [ "$ready_rc" -ne 0 ]; then
  echo "precheck.sh: ready.sh failed (rc=$ready_rc) -- could not determine readiness, skipping this run" >&2
  exit 2
fi

if [ -z "$issues" ]; then
  exit 1
fi

exit 0
