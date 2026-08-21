#!/usr/bin/env bash
# Orca automation precheck: exit 0 to run, non-zero to skip.
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

# ready.sh prints nothing (and exits non-zero, message on its own stderr)
# both when there is genuinely no ready issue and when it can't safely
# answer at all (a `gh` API failure) -- either way that's "skip", never
# "run", which is the fail-closed direction for a precheck.
[ -n "$("$READY")" ]
