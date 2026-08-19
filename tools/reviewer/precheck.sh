#!/usr/bin/env bash
# Orca automation precheck: exit 0 to let the run proceed, non-zero to skip it.
# Skipped runs are cheap and recorded in `orca automations runs`, so this keeps
# the reviewer pool from burning an agent session on an empty queue.
set -euo pipefail
cd "$(dirname "$0")/../.."
./tools/reviewer/lease.sh sweep >/dev/null 2>&1 || true
# Run if there is anything to review OR anything now clear to merge; an
# approval arriving hours after the review must still wake the pool.
[ -n "$(./tools/reviewer/lease.sh claimable)$(./tools/reviewer/lease.sh mergeable)" ]
