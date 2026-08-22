#!/usr/bin/env bash
set -euo pipefail
ROSTER="${POOL_ROSTER:-$(dirname "$0")/roster.tsv}"

rows() { grep -v '^[[:space:]]*#' "$ROSTER" | grep -v '^[[:space:]]*$'; }

: "${1:?usage: roster.sh <implementers|reviewers-above <tier>|max-parallel>}"
case "$1" in
  implementers)
    rows | awk -F'\t' '$1=="implement" {print $2"\t"$3"\t"$4"\t"$5}' | sort -t$'\t' -k4,4n ;;
  reviewers-above)
    rows | awk -F'\t' -v t="${2:?tier required}" \
      '$1=="review" && $5+0 > t+0 {print $2"\t"$3"\t"$4"\t"$5}' | sort -t$'\t' -k4,4n ;;
  max-parallel)
    rows | awk -F'\t' '$1=="implement"' | wc -l | tr -d ' ' ;;
  *) echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
