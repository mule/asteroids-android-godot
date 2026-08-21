#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2' got '$3'"; fails=$((fails+1)); fi; }

# Offline: labels are injected so the test does not depend on repo state.
route(){ POOL_LABELS="$1" ./tools/implementer/route.sh 99; }

check "unlabelled goes to the lowest tier" "antigravity" "$(route "" | cut -f1)"
check "unlabelled is tier 1"               "1"           "$(route "" | cut -f4)"
check "agent:claude overrides"             "claude"      "$(route "agent:claude" | cut -f1)"
check "agent:claude is tier 2"             "2"           "$(route "agent:claude" | cut -f4)"
check "claude carries its effort"          "high"        "$(route "agent:claude" | cut -f3)"
check "unknown agent falls back"           "antigravity" "$(route "agent:nonesuch" | cut -f1)"

[ "$fails" -eq 0 ] || exit 1
