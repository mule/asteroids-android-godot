#!/usr/bin/env bash
# Mutual exclusion for agent pools, arbitrated by GitHub.
#
# A lock is a git ref under refs/<ns>/<key>. Ref creation is an atomic
# compare-and-swap: the first agent to POST /git/refs wins, every later agent
# gets HTTP 422 "Reference already exists". Labels cannot do this — two agents
# can both add one and both succeed.
set -euo pipefail

SLUG="${POOL_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
AGENT="${POOL_AGENT_ID:-$(hostname)-$$}"

ref_of() { printf 'refs/%s/%s' "$1" "$2"; }

# Exit-code contract callers rely on (tools/implementer/ready.sh in
# particular): 0 = a trustworthy list, possibly empty, because the
# namespace genuinely holds no locks. Non-zero = the `gh api` call itself
# failed (auth, rate limit, network) and the list must NOT be trusted as
# "nothing held" -- an empty held-set during an outage is how two agents
# end up claiming the same issue. Capture the API call's own exit status
# before any further processing, rather than swallowing it with a trailing
# `|| true` on the whole pipeline (that used to make a failed call look
# identical to a genuinely empty namespace).
held() {
  local out
  out=$(gh api "repos/$SLUG/git/matching-refs/$1/" -q '.[].ref' 2>/dev/null) || return 1
  [ -n "$out" ] || return 0
  printf '%s\n' "$out" | sed "s|^refs/$1/||"
}

claim() { # claim <ns> <key> <sha>
  gh api "repos/$SLUG/git/refs" -f ref="$(ref_of "$1" "$2")" -f sha="$3" \
    >/dev/null 2>&1 || return 1
  echo "$2"
}

release() { # release <ns> <key>
  gh api -X DELETE "repos/$SLUG/git/refs/$1/$2" >/dev/null 2>&1 || true
}

# Delete refs whose key is not in the live list, so a namespace stays the size
# of the open queue rather than growing with the repo's history.
gc() {
  local ns=$1; shift
  local live=" $* " key
  for key in $(held "$ns"); do
    case "$live" in *" $key "*) ;; *) release "$ns" "$key" ;; esac
  done
}

# "<key><TAB><sha>" for every ref held in namespace <ns> — the namespace-
# generic form of "what has this pool marked clean, and at exactly which
# commit". The reviewer pool uses this for its reviewer-passed/pr-N sha pin
# (tools/reviewer/lease.sh's passed_at); one bulk API call rather than one
# `sha` lookup per key, which matters in a polling loop.
shas() {
  gh api "repos/$SLUG/git/matching-refs/$1/" 2>/dev/null \
    | jq -r --arg p "refs/$1/" '.[] | "\(.ref | ltrimstr($p))\t\(.object.sha)"' \
    || true
}

# The sha a single key's ref points at, empty if the ref does not exist.
# On a 404, `gh api` exits non-zero but still writes the error JSON body to
# stdout (not stderr) — capture into a var first so a missing ref truly
# yields nothing, rather than leaking `{"message":"Not Found",...}` as if it
# were a sha.
sha() { # sha <ns> <key>
  local out
  out=$(gh api "repos/$SLUG/git/ref/$1/$2" -q .object.sha 2>/dev/null) || out=""
  printf '%s\n' "$out"
}

# ISO timestamp of the newest lease marker comment on issue-or-PR <n>, empty
# if there is none. Two failure modes matter here, both from a key whose
# derived <n> isn't a real issue/PR number: (1) under `set -e`, a failing
# `gh api` would abort the whole script rather than let the caller's
# `[ -n "$ts" ] || continue` guard run — one bad key would kill sweep()
# before it reaches the rest; (2) on failure `gh api` still writes the error
# JSON body to stdout (not stderr), so a bare `|| true` alone would still
# leak that body out as if it were a timestamp, which `date -u -d` in
# sweep() would then fail to parse and abort on anyway. Capture first, so a
# failed lookup truly produces nothing.
stamp() {
  local out
  out=$(gh api "repos/$SLUG/issues/$1/comments" --paginate \
    -q '.[] | select(.body | contains("<!-- pool-lease")) | .created_at' \
    2>/dev/null) || return 0
  printf '%s\n' "$out" | tail -1
}

note() { # note <n> <text> — record who holds the lease, for stale detection
  gh pr comment "$1" --repo "$SLUG" >/dev/null 2>&1 --body \
    "<!-- pool-lease agent=$AGENT at=$(date -u +%Y-%m-%dT%H:%M:%SZ) -->
🤖 $2" \
  || gh issue comment "$1" --repo "$SLUG" >/dev/null --body \
    "<!-- pool-lease agent=$AGENT at=$(date -u +%Y-%m-%dT%H:%M:%SZ) -->
🤖 $2"
}

# Break locks whose newest lease marker is older than <ttl-min>.
sweep() { # sweep <ns> <ttl-min>
  local ns=$1 ttl=$2 key ts age now
  now=$(date -u +%s)
  for key in $(held "$ns"); do
    ts=$(stamp "${key##*-}")
    [ -n "$ts" ] || continue
    age=$(( (now - $(date -u -d "$ts" +%s)) / 60 ))
    if [ "$age" -ge "$ttl" ]; then
      echo "breaking stale lock $ns/$key (${age}m)" >&2
      release "$ns" "$key"
    fi
  done
}

# NOTE: a literal { or } inside "${1:?word}"'s word closes the expansion at
# the first bare }, before bash ever gets to the real closing brace — the
# case dispatch below would then always see "claim ...}" and never match a
# subcommand. Keep the required-arg check and the usage text separate.
: "${1:?usage: lock.sh <claim|release|held|gc|shas|sha|sweep|stamp|note> ...}"
case "$1" in
  claim)   claim   "$2" "$3" "$4" ;;
  release) release "$2" "$3" ;;
  held)    held    "$2" ;;
  gc)      ns=$2; shift 2; gc "$ns" "$@" ;;
  shas)    shas    "$2" ;;
  sha)     sha     "$2" "$3" ;;
  sweep)   sweep   "$2" "$3" ;;
  stamp)   stamp   "$2" ;;
  note)    note    "$2" "$3" ;;
  *) echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
