# Epic Implementation Pool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a scheduled agent pool that implements epic #43's child issues and opens PRs, and make the existing review pool safe to merge them unattended.

**Architecture:** Two Orca automations share one GitHub-arbitrated mutex (`tools/pool/lock.sh`). The implementer pool computes readiness from the `## Dependencies` line in each issue body, routes work through a tiered roster, and opens PRs. The review pool merges only when real CI is green and a strictly-higher-tier reviewer passed.

**Tech Stack:** POSIX shell + `gh` CLI + `jq`, Godot 4.7.1 headless, GitHub Actions, Orca CLI (`automations`, `orchestration`).

**Spec:** `docs/superpowers/specs/2026-08-20-implementation-pool-design.md`

## Global Constraints

- Godot binary is `/home/japurane/.local/bin/godot` (4.7.1.stable). Invoke as `godot --headless --path . --script <path>`.
- All shell scripts: `#!/usr/bin/env bash` + `set -euo pipefail`, `chmod +x`, and must pass `bash -n`.
- Repo slug is `mule/asteroids-android-godot`; `gh` authenticates as `mule`.
- Lock namespaces are disjoint: `refs/reviewer-locks/pr-N`, `refs/implementer-locks/issue-N`.
- Epic membership test is exactly: issue body contains `Parent epic: #43`.
- Lease TTL is 90 minutes. Implementer give-up deadline is 60 minutes.
- `MAX_PARALLEL` = number of `implement` rows in `tools/pool/roster.tsv`.
- Never weaken the tier invariant: a PR is reviewed only by a roster row whose tier is strictly greater than the PR's `impl-tier:<n>` label.
- Scripts must run from a fresh clone of `main` with no local state.

---

### Task 1: Hardened Godot test runner

A broken script under test currently prints `SCRIPT ERROR` and then hangs — `_init()` aborts before `quit()`, so the SceneTree never exits. Exit code alone is not a trustworthy signal.

**Files:**
- Create: `tools/tests/run_godot_test.sh`
- Create: `tests/pool/test_run_godot_test.sh`

**Interfaces:**
- Produces: `run_godot_test.sh <script-path> [timeout-seconds]` → exit 0 only if Godot exited 0, within the timeout, and printed no `SCRIPT ERROR` / `ERROR: Failed loading` / `Parse Error` line.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/pool/test_run_godot_test.sh <<'EOF'
#!/usr/bin/env bash
# Verifies the runner catches all three failure modes, not just exit codes.
set -uo pipefail
cd "$(dirname "$0")/../.."
R=./tools/tests/run_godot_test.sh
fails=0
check() { # check <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want rc=$2 got rc=$3"; fails=$((fails+1)); fi
}

# 1. A healthy test script passes.
$R tests/test_asteroid_collisions.gd 180 >/dev/null 2>&1
check "healthy suite passes" 0 $?

# 2. A script that errors then hangs must fail, not time out the whole CI job.
cat > tests/_fixture_hang.gd <<'GD'
extends SceneTree
func _init() -> void:
	var s := load("res://tests/_fixture_missing.gd")
	var obj = s.new()
	print("ALL TESTS PASSED")
	quit(0)
GD
$R tests/_fixture_hang.gd 20 >/dev/null 2>&1
check "erroring+hanging script fails" 1 $?
rm -f tests/_fixture_hang.gd tests/_fixture_hang.gd.uid

# 3. A script that prints a script error but still exits 0 must fail.
cat > tests/_fixture_silent.gd <<'GD'
extends SceneTree
func _init() -> void:
	# Errors at engine level but never dereferences, so it reaches quit(0).
	# This is the exact shape Finding 6 describes: green exit, broken run.
	var s = load("res://tests/_fixture_missing.gd")
	if s == null:
		pass
	print("ALL TESTS PASSED")
	quit(0)
GD
$R tests/_fixture_silent.gd 30 >/dev/null 2>&1
check "error printed but rc=0 fails" 1 $?
rm -f tests/_fixture_silent.gd tests/_fixture_silent.gd.uid

[ "$fails" -eq 0 ] || exit 1
EOF
chmod +x tests/pool/test_run_godot_test.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/pool/test_run_godot_test.sh`
Expected: FAIL — `./tools/tests/run_godot_test.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

```bash
mkdir -p tools/tests
cat > tools/tests/run_godot_test.sh <<'EOF'
#!/usr/bin/env bash
# Run one Godot test script and decide honestly whether it passed.
#
# Exit code alone is not enough. A script whose dependency fails to compile
# aborts _init() before quit(), leaving the SceneTree running forever; and a
# script can print SCRIPT ERROR and still reach quit(0). This wrapper treats
# a timeout and any engine-level error line as failures.
set -uo pipefail

GODOT="${GODOT_BIN:-/home/japurane/.local/bin/godot}"
script="${1:?usage: run_godot_test.sh <script-path> [timeout-seconds]}"
limit="${2:-180}"
log=$(mktemp)
trap 'rm -f "$log"' EXIT

timeout --signal=KILL "$limit" \
  "$GODOT" --headless --path . --script "$script" >"$log" 2>&1
rc=$?

if [ "$rc" -eq 137 ]; then
  echo "FAIL $script: no exit within ${limit}s (script likely errored before quit())" >&2
  tail -20 "$log" >&2
  exit 1
fi

if grep -qE 'SCRIPT ERROR|Parse Error|ERROR: Failed loading|ERROR: Attempt to open script' "$log"; then
  echo "FAIL $script: engine reported an error" >&2
  grep -E 'SCRIPT ERROR|Parse Error|ERROR:' "$log" | head -10 >&2
  exit 1
fi

if [ "$rc" -ne 0 ]; then
  echo "FAIL $script: exit code $rc" >&2
  tail -20 "$log" >&2
  exit 1
fi

echo "PASS $script"
EOF
chmod +x tools/tests/run_godot_test.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/pool/test_run_godot_test.sh`
Expected: three `ok -` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/tests/run_godot_test.sh tests/pool/test_run_godot_test.sh
git commit -m "Fail Godot tests that error or hang instead of reporting green

A script whose dependency fails to compile aborts _init() before quit(),
so the SceneTree never exits and the suite reports nothing. Another can
print SCRIPT ERROR and still reach quit(0). The runner now treats a
timeout and any engine error line as failures alongside the exit code.

Found as Finding 6 of the #60 review."
```

---

### Task 2: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: a required check named `tests` whose conclusion the merge gate reads via `gh pr view --json statusCheckRollup`.

- [ ] **Step 1: Write the workflow**

```yaml
name: tests
on:
  pull_request:
  push:
    branches: [main]

jobs:
  tests:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4

      - name: Install Godot 4.7.1
        run: |
          set -euo pipefail
          V=4.7.1
          curl -fsSL -o godot.zip \
            "https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_linux.x86_64.zip"
          unzip -q godot.zip
          mkdir -p "$HOME/.local/bin"
          mv Godot_v${V}-stable_linux.x86_64 "$HOME/.local/bin/godot"
          chmod +x "$HOME/.local/bin/godot"

      - name: Import project resources
        run: $HOME/.local/bin/godot --headless --path . --quit || true

      - name: Godot suites
        run: |
          set -euo pipefail
          for t in tests/test_*.gd; do
            GODOT_BIN="$HOME/.local/bin/godot" ./tools/tests/run_godot_test.sh "$t" 300
          done

      - name: Python suites
        run: |
          python3 -m pip install --quiet pytest
          python3 -m pytest tests/asset_pipeline -q

      - name: Shell suites
        run: |
          set -euo pipefail
          for t in tests/pool/test_*.sh; do bash "$t"; done
```

- [ ] **Step 2: Verify it parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml ok')"`
Expected: `yaml ok`

- [ ] **Step 3: Commit and confirm the check appears**

```bash
git add .github/workflows/ci.yml
git commit -m "Add CI running Godot, python, and shell suites"
git push
gh run list --limit 1
```

Expected: a workflow run named `tests` appears. Wait for it and confirm `conclusion: success` before continuing — the merge gate will depend on this check existing.

**Note for the executor:** `tests/pool/test_run_godot_test.sh` intentionally runs Godot three times; if CI proves too slow, raise `timeout-minutes` rather than deleting cases.

---

### Task 3: Extract the shared lock core

Behaviour-preserving refactor. The reviewer pool must work identically afterwards.

**Files:**
- Create: `tools/pool/lock.sh`
- Create: `tests/pool/test_lock.sh`
- Modify: `tools/reviewer/lease.sh` (delegate lock operations)

**Interfaces:**
- Produces:
  - `lock.sh claim <ns> <key> <sha>` → exit 0 and echo `<key>` if won, exit 1 if held
  - `lock.sh release <ns> <key>` → always exit 0
  - `lock.sh held <ns>` → one key per line
  - `lock.sh gc <ns> <live-key>...` → deletes refs for keys not listed
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/pool/test_lock.sh <<'EOF'
#!/usr/bin/env bash
# Integration test against real GitHub: ref creation is the mutex, so a
# fake would test nothing. Uses a throwaway namespace and cleans up.
set -uo pipefail
cd "$(dirname "$0")/../.."
L=./tools/pool/lock.sh
NS=selftest-locks
KEY=probe-1
SHA=$(gh api repos/mule/asteroids-android-godot/git/ref/heads/main -q .object.sha)
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want $2 got $3"; fails=$((fails+1)); fi; }

$L release "$NS" "$KEY" >/dev/null 2>&1

$L claim "$NS" "$KEY" "$SHA" >/dev/null 2>&1; check "first claim wins" 0 $?
$L claim "$NS" "$KEY" "$SHA" >/dev/null 2>&1; check "second claim loses" 1 $?
check "held lists the key" "$KEY" "$($L held "$NS")"

$L gc "$NS" "some-other-key" >/dev/null 2>&1
check "gc drops keys not live" "" "$($L held "$NS")"

$L claim "$NS" "$KEY" "$SHA" >/dev/null 2>&1
$L release "$NS" "$KEY" >/dev/null 2>&1
check "release frees the key" "" "$($L held "$NS")"

[ "$fails" -eq 0 ] || exit 1
EOF
chmod +x tests/pool/test_lock.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/pool/test_lock.sh`
Expected: FAIL — `./tools/pool/lock.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

```bash
mkdir -p tools/pool
cat > tools/pool/lock.sh <<'EOF'
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

held() {
  gh api "repos/$SLUG/git/matching-refs/$1/" -q '.[].ref' 2>/dev/null \
    | sed "s|^refs/$1/||" || true
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

# ISO timestamp of the newest lease marker comment on issue-or-PR <n>.
# GitHub serves PR and issue comments from the same endpoint, so one
# implementation covers both pools.
stamp() {
  gh api "repos/$SLUG/issues/$1/comments" --paginate \
    -q '.[] | select(.body | contains("<!-- pool-lease")) | .created_at' \
    2>/dev/null | tail -1
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

case "${1:?usage: lock.sh {claim|release|held|gc|sweep|stamp|note} ...}" in
  claim)   claim   "$2" "$3" "$4" ;;
  release) release "$2" "$3" ;;
  held)    held    "$2" ;;
  gc)      ns=$2; shift 2; gc "$ns" "$@" ;;
  sweep)   sweep   "$2" "$3" ;;
  stamp)   stamp   "$2" ;;
  note)    note    "$2" "$3" ;;
  *) echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
EOF
chmod +x tools/pool/lock.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/pool/test_lock.sh`
Expected: five `ok -` lines, exit 0.

- [ ] **Step 5: Migrate the reviewer pool onto it**

Replace the body of `claim`, `release`, and `held_prs` in `tools/reviewer/lease.sh` with delegation, leaving every other function and all CLI behaviour unchanged:

```bash
LOCK=./tools/pool/lock.sh
NS=reviewer-locks

held_prs() { $LOCK held "$NS" | sed 's/^pr-//'; }

claim() {
  local pr=$1 sha
  sha=$(gh api "repos/$SLUG/pulls/$pr" -q .head.sha)
  $LOCK claim "$NS" "pr-$pr" "$sha" >/dev/null || return 1
  $LOCK note "$pr" "Review lease held by \`${POOL_AGENT_ID:-$REVIEWER_ID}\`."
  gh pr edit "$pr" --repo "$SLUG" --add-label review-in-progress >/dev/null 2>&1 || true
  echo "$pr"
}

release() {
  local pr=$1
  $LOCK release "$NS" "pr-$pr"
  gh pr edit "$pr" --repo "$SLUG" --remove-label review-in-progress >/dev/null 2>&1 || true
}
```

- [ ] **Step 6: Verify the reviewer pool still behaves identically**

Run:
```bash
bash -n tools/reviewer/lease.sh
./tools/reviewer/lease.sh claimable
REVIEWER_ID=a ./tools/reviewer/lease.sh claim 60 && echo "A won"
REVIEWER_ID=b ./tools/reviewer/lease.sh claim 60 || echo "B lost (correct)"
./tools/reviewer/lease.sh holders
./tools/reviewer/lease.sh release 60
./tools/reviewer/lease.sh holders
```
Expected: A wins, B loses, holders lists #60 then nothing. Same as before the refactor.

- [ ] **Step 7: Commit**

```bash
git add tools/pool/lock.sh tests/pool/test_lock.sh tools/reviewer/lease.sh
git commit -m "Extract the pool lock into tools/pool/lock.sh

Both pools need the same mutex, and the mutex is the only thing standing
between two agents and the same task. It should exist once."
```

---

### Task 4: Tiered roster

**Files:**
- Create: `tools/pool/roster.tsv`
- Create: `tools/pool/roster.sh`
- Create: `tests/pool/test_roster.sh`

**Interfaces:**
- Produces:
  - `roster.sh implementers` → `agent<TAB>model<TAB>effort<TAB>tier`, ascending tier
  - `roster.sh reviewers-above <tier>` → same shape, rows with tier strictly greater
  - `roster.sh max-parallel` → count of `implement` rows
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/pool/test_roster.sh <<'EOF'
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
EOF
chmod +x tests/pool/test_roster.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/pool/test_roster.sh`
Expected: FAIL — `./tools/pool/roster.sh: No such file or directory`

- [ ] **Step 3: Write the roster and its reader**

```bash
cat > tools/pool/roster.tsv <<'EOF'
# role	agent	model	effort	tier
# A PR may only be reviewed by a row whose tier is strictly greater than the
# tier that built it. That keeps a model from clearing its own work while
# still letting one provider fill both roles at different effort levels.
#
# Orca's worker-start --model/--effort covers Claude, Codex and Cursor only.
# Antigravity's model is declared here but configured on antigravity's side.
implement	antigravity	3.7-flash	-	1
implement	claude	opus	high	2
review	claude	opus	max	3
EOF

cat > tools/pool/roster.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROSTER="${POOL_ROSTER:-$(dirname "$0")/roster.tsv}"

rows() { grep -v '^[[:space:]]*#' "$ROSTER" | grep -v '^[[:space:]]*$'; }

case "${1:?usage: roster.sh {implementers|reviewers-above <tier>|max-parallel}}" in
  implementers)
    rows | awk -F'\t' '$1=="implement" {print $2"\t"$3"\t"$4"\t"$5}' | sort -t$'\t' -k4,4n ;;
  reviewers-above)
    rows | awk -F'\t' -v t="${2:?tier required}" \
      '$1=="review" && $5+0 > t+0 {print $2"\t"$3"\t"$4"\t"$5}' | sort -t$'\t' -k4,4n ;;
  max-parallel)
    rows | awk -F'\t' '$1=="implement"' | wc -l | tr -d ' ' ;;
  *) echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
EOF
chmod +x tools/pool/roster.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/pool/test_roster.sh`
Expected: six `ok -` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/pool/roster.tsv tools/pool/roster.sh tests/pool/test_roster.sh
git commit -m "Add the tiered agent roster

Tier is (model, effort), not model alone, so opus at max effort can review
opus at high effort without a model ever clearing its own work."
```

---

### Task 5: Dependency-driven readiness

**Files:**
- Create: `tools/implementer/deps.sh`
- Create: `tools/implementer/ready.sh`
- Create: `tests/pool/test_deps.sh`

**Interfaces:**
- Consumes: `tools/pool/lock.sh held implementer-locks` (Task 3).
- Produces:
  - `deps.sh` — reads an issue body on **stdin**, prints one required issue number per line. Pure and offline, so it is unit-testable.
  - `ready.sh` — prints claimable issue numbers, ascending.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/pool/test_deps.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
D=./tools/implementer/deps.sh
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want '$2' got '$3'"; fails=$((fails+1)); fi; }

check "single dependency" "44" "$(printf '## Dependencies\n\nRequires #44.\n' | $D | tr '\n' ' ' | xargs)"
check "multiple dependencies" "44 45" "$(printf '## Dependencies\n\nRequires #44, #45.\n' | $D | tr '\n' ' ' | xargs)"
check "no dependencies section" "" "$(printf '## Goal\n\nDo a thing.\n' | $D)"
check "empty dependencies" "" "$(printf '## Dependencies\n\nNone.\n' | $D)"
check "issue refs elsewhere are ignored" "44" \
  "$(printf 'Parent epic: #43\n\n## Goal\n\nSee #99.\n\n## Dependencies\n\nRequires #44.\n' | $D | tr '\n' ' ' | xargs)"
check "real issue #46 needs 44 and 45" "44 45" \
  "$(gh issue view 46 --json body -q .body | $D | tr '\n' ' ' | xargs)"

[ "$fails" -eq 0 ] || exit 1
EOF
chmod +x tests/pool/test_deps.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/pool/test_deps.sh`
Expected: FAIL — `./tools/implementer/deps.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
mkdir -p tools/implementer
cat > tools/implementer/deps.sh <<'EOF'
#!/usr/bin/env bash
# Read an issue body on stdin, print one required issue number per line.
#
# Scoped to the `## Dependencies` section on purpose: issue bodies mention
# other issues in prose, and treating those as blockers would wedge the pool.
set -euo pipefail
awk '
  /^##[[:space:]]/ { in_deps = ($0 ~ /^##[[:space:]]+Dependencies/) ; next }
  in_deps { print }
' | grep -oE '#[0-9]+' | tr -d '#' | sort -un
EOF
chmod +x tools/implementer/deps.sh

cat > tools/implementer/ready.sh <<'EOF'
#!/usr/bin/env bash
# Print epic child issues that are claimable right now, ascending.
#
# An issue is claimable when it is open, belongs to the epic, carries neither
# impl-blocked nor hold, has no open PR, is unlocked, and every issue named in
# its `## Dependencies` section is CLOSED. Strict by design: implementers
# always build on merged code, so parallelism comes from the width of the
# dependency graph rather than from speculating on unmerged branches.
set -euo pipefail
cd "$(dirname "$0")/../.."

SLUG="${POOL_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
EPIC="${POOL_EPIC:-43}"
NS=implementer-locks

locked=" $(./tools/pool/lock.sh held "$NS" | sed 's/^issue-//' | tr '\n' ' ') "
linked=" $(gh pr list --repo "$SLUG" --state open --limit 100 --json body,title \
             -q '.[] | "\(.title) \(.body)"' | grep -oE '#[0-9]+' | tr -d '#' | sort -u | tr '\n' ' ') "

gh issue list --repo "$SLUG" --state open --limit 100 \
  --json number,body,labels \
  -q '.[] | select(.body | contains("Parent epic: #'"$EPIC"'"))
          | select([.labels[].name] | index("impl-blocked") | not)
          | select([.labels[].name] | index("hold") | not)
          | "\(.number)\t\(.body | @base64)"' \
| while IFS=$'\t' read -r n body64; do
    case "$locked" in *" $n "*) continue ;; esac
    case "$linked" in *" $n "*) continue ;; esac
    blocked=no
    for dep in $(printf '%s' "$body64" | base64 -d | ./tools/implementer/deps.sh); do
      state=$(gh issue view "$dep" --repo "$SLUG" --json state -q .state 2>/dev/null || echo OPEN)
      [ "$state" = "CLOSED" ] || { blocked=yes; break; }
    done
    [ "$blocked" = no ] && echo "$n"
  done | sort -n
EOF
chmod +x tools/implementer/ready.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/pool/test_deps.sh`
Expected: six `ok -` lines, exit 0.

- [ ] **Step 5: Verify readiness against the live epic**

Run: `./tools/implementer/ready.sh`
Expected today: **empty**. #44 has open PR #60 so it is excluded by the linked-PR rule; #45–#59 are all blocked on unclosed dependencies. After #60 merges and #44 closes, expect `45 47 48 50`.

Record what you actually observe. If the output is non-empty today, stop and investigate before continuing — an over-permissive `ready.sh` is how two agents end up on the same work.

- [ ] **Step 6: Commit**

```bash
git add tools/implementer/deps.sh tools/implementer/ready.sh tests/pool/test_deps.sh
git commit -m "Compute implementer readiness from the issue dependency graph

Every child issue already carries 'Requires #N' under ## Dependencies, so the
schedule follows the graph rather than a curated list that drifts."
```

---

### Task 6: Routing and precheck

**Files:**
- Create: `tools/implementer/route.sh`
- Create: `tools/implementer/precheck.sh`
- Create: `tests/pool/test_route.sh`

**Interfaces:**
- Consumes: `roster.sh implementers` (Task 4).
- Produces: `route.sh <issue-number>` → `agent<TAB>model<TAB>effort<TAB>tier` for that issue.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/pool/test_route.sh <<'EOF'
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
EOF
chmod +x tests/pool/test_route.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/pool/test_route.sh`
Expected: FAIL — `./tools/implementer/route.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
cat > tools/implementer/route.sh <<'EOF'
#!/usr/bin/env bash
# Pick the implementer configuration for an issue.
#
# An `agent:<id>` label wins, so the human steers the hard work to the
# high-tier model. Everything else goes to the lowest tier, which is the
# cheap default. An unknown agent falls back rather than failing the run.
set -euo pipefail
cd "$(dirname "$0")/../.."

n="${1:?usage: route.sh <issue-number>}"
SLUG="${POOL_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

labels="${POOL_LABELS-$(gh issue view "$n" --repo "$SLUG" --json labels \
          -q '[.labels[].name] | join(",")' 2>/dev/null || true)}"

want=$(printf '%s' "$labels" | tr ',' '\n' | sed -n 's/^agent://p' | head -1)

if [ -n "$want" ]; then
  row=$(./tools/pool/roster.sh implementers | awk -F'\t' -v a="$want" '$1==a {print; exit}')
  [ -n "$row" ] && { printf '%s\n' "$row"; exit 0; }
fi

./tools/pool/roster.sh implementers | head -1
EOF
chmod +x tools/implementer/route.sh

cat > tools/implementer/precheck.sh <<'EOF'
#!/usr/bin/env bash
# Orca automation precheck: exit 0 to run, non-zero to skip.
# Skipped runs are cheap and recorded, so an idle epic costs no agent sessions.
set -euo pipefail
cd "$(dirname "$0")/../.."
./tools/pool/lock.sh sweep implementer-locks 90 >/dev/null 2>&1 || true
[ -n "$(./tools/implementer/ready.sh)" ]
EOF
chmod +x tools/implementer/precheck.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/pool/test_route.sh`
Expected: six `ok -` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/implementer/route.sh tools/implementer/precheck.sh tests/pool/test_route.sh
git commit -m "Route issues to implementers by label, defaulting to the cheap tier"
```

---

### Task 7: Agent briefs and the automation

**Files:**
- Create: `tools/implementer/COORDINATOR.md`
- Create: `tools/implementer/IMPLEMENTER.md`

**Interfaces:**
- Consumes: `ready.sh`, `route.sh`, `lock.sh`, `roster.sh` (Tasks 3–6).
- Produces: an Orca automation named `Epic implementation pool`.

- [ ] **Step 1: Write the coordinator brief**

```bash
cat > tools/implementer/COORDINATOR.md <<'EOF'
# Epic implementation pool — coordinator

You are the scheduled coordinator for epic #43's implementation pool.
You never write feature code yourself. You claim issues and fan them out.

## Loop

1. `./tools/pool/lock.sh sweep implementer-locks 90` — return crashed agents'
   issues to the pool.
2. `./tools/implementer/ready.sh` — the queue. Empty means stop now and report
   "nothing ready"; do not invent work, and never relax a dependency.
3. Compute the budget:
   `MAX=$(./tools/pool/roster.sh max-parallel)`,
   `HELD=$(./tools/pool/lock.sh held implementer-locks | wc -l)`,
   claim at most `MAX - HELD` issues. The subtraction matters: the lock stops
   two agents taking the same issue, not a second scheduled run doubling the
   fleet while the first is still working.
4. Bind a Run: reuse the one whose objective is `Epic implementation pool`
   from `orca orchestration run-list --json`, else
   `orca orchestration run-create --objective "Epic implementation pool" --json`.
5. For each issue in the budget, ascending:
   - `./tools/pool/lock.sh claim implementer-locks issue-<n> $(git rev-parse origin/main)`
     — **non-zero means another agent won the race; skip that issue silently.**
   - `./tools/pool/lock.sh note <n> "Implementation lease held."`
   - `read -r AGENT MODEL EFFORT TIER < <(./tools/implementer/route.sh <n>)`
   - `orca orchestration task-create --task-title "implement #<n>" --spec "$(sed "s/<ISSUE>/<n>/g; s/<TIER>/$TIER/g" tools/implementer/IMPLEMENTER.md)" --json`
   - `orca orchestration worker-start --task <task_id> --worktree new-top-level \
        --name "impl-<n>" --repo name:asteroids-android --base-branch main \
        --agent "$AGENT" --setup run --json`
     Add `--model "$MODEL" --effort "$EFFORT"` only when `MODEL` is not `-`;
     Orca supports those flags for Claude, Codex and Cursor only.
   - If `worker-start` exits non-zero, release the lock immediately. A held
     lock with no live worker stalls the pool silently.
6. Start every worker before waiting on any of them.
7. `orca orchestration check --wait --types worker_done,escalation,question \
      --timeout-ms 3600000 --json`, in a rolling loop until every dispatch
   settles. Answer `question` with `orchestration reply`. On a failed
   `worker_done`, release that issue's lock. After each settled dispatch,
   `orca orchestration worker-release --dispatch <id> --json`.
   A timeout or `{count:0}` is a checkpoint, not a failure.
8. Report: PRs opened, issues blocked, issues skipped on a lost race.

## Rules

- The lock grants implementation rights. No lock, no work.
- Never merge anything. Never add the `approved` label.
- Never edit an issue's `## Dependencies` section to unblock yourself.
EOF
```

- [ ] **Step 2: Write the implementer brief**

```bash
cat > tools/implementer/IMPLEMENTER.md <<'EOF'
# Implement issue #<ISSUE>

You hold the implementation lease on issue #<ISSUE>. Your worktree is a fresh
branch off `main`. Your roster tier is <TIER>.

1. `gh issue view <ISSUE>` and read `docs/superpowers/specs/` for the epic's
   intent. The issue's `## Interfaces produced` section is a contract later
   issues depend on — match those names and signatures exactly.
2. Implement against the issue's `## Acceptance criteria`, test-first wherever
   the issue names a test file.
3. Run the full suite:
   `for t in tests/test_*.gd; do ./tools/tests/run_godot_test.sh "$t" 300; done`
   and `python3 -m pytest tests/asset_pipeline -q`.
   Never push a red branch.
4. Commit, push, and open a PR whose body contains `Closes #<ISSUE>`.
   Label it `impl-tier:<TIER>` — the review pool uses this to pick a reviewer
   of strictly higher tier, so omitting it blocks the merge.
5. **Always**, success or failure:
   `./tools/pool/lock.sh release implementer-locks issue-<ISSUE>`
6. Report once:
   `orca orchestration send --type worker_done --subject "<ISSUE> <opened|blocked>" \
      --body "<what you built, what remains>" --task-id <task_id> \
      --dispatch-id <dispatch_id> --outcome <succeeded|failed> --json`

## Give-up path

If the suite will not pass, the issue is ambiguous, or 60 minutes have passed
since you took the lease: push what you have as a **draft** PR, run
`gh issue edit <ISSUE> --add-label impl-blocked` with a comment naming exactly
what stopped you and what you need decided, release the lock, and report
`--outcome failed`. Draft PRs are invisible to the review pool, so partial work
is safe to leave. Do not grind past the deadline.

Do not touch any issue other than #<ISSUE>. Do not merge. Do not add the
`approved` label. Do not edit `## Dependencies` on any issue.
EOF
```

- [ ] **Step 3: Create the required labels**

```bash
gh label create impl-blocked --color B60205 --description "Implementation stopped; needs a human decision" || true
gh label create hold         --color 000000 --description "Emergency brake: no pool may act on this" || true
gh label create impl-tier:1  --color C5DEF5 --description "Built by a tier-1 implementer" || true
gh label create impl-tier:2  --color C5DEF5 --description "Built by a tier-2 implementer" || true
gh label create agent:claude --color 5319E7 --description "Route this issue to claude" || true
```

- [ ] **Step 4: Commit, then create the automation disabled**

```bash
git add tools/implementer/COORDINATOR.md tools/implementer/IMPLEMENTER.md
git commit -m "Add implementer pool agent briefs"
git push

orca automations create \
  --name "Epic implementation pool" \
  --repo name:asteroids-android \
  --trigger "0 * * * *" \
  --timezone Europe/Helsinki \
  --provider claude \
  --workspace-mode new-per-run \
  --base-branch main \
  --precheck "./tools/implementer/precheck.sh" \
  --precheck-timeout 120 \
  --disabled \
  --prompt "You are the epic implementation pool coordinator. Read tools/implementer/COORDINATOR.md and follow it exactly. Do not write feature code yourself." \
  --json
```

- [ ] **Step 5: Verify the precheck skips correctly**

Run it twice:
```bash
./tools/implementer/precheck.sh; echo "rc=$?"
./tools/implementer/precheck.sh; echo "rc=$?"
```
Expected today: `rc=1` both times (nothing ready — see Task 5 Step 5), with no
comments posted and no refs created between the runs. That is the idempotence
property: a run with no new work must claim nothing and say nothing. Confirm
with `./tools/pool/lock.sh held implementer-locks` printing nothing.

---

### Task 8: Flip the merge gate to autonomous

**Do not start this task until CI from Task 2 has produced at least one green run on a real PR.** Until then `checks=none`, and this change would hold every PR forever.

**Files:**
- Modify: `tools/reviewer/merge-gate.sh`
- Create: `tests/pool/test_merge_gate.sh`

**Interfaces:**
- Consumes: `roster.sh reviewers-above` (Task 4), the `tests` check (Task 2).
- Produces: exit 0 merge / 1 hold / 2 awaiting sign-off, unchanged in meaning.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/pool/test_merge_gate.sh <<'EOF'
#!/usr/bin/env bash
# Drives the gate's decision logic through injected facts, so every row of the
# policy table is exercised without needing six real PRs.
set -uo pipefail
cd "$(dirname "$0")/../.."
G=./tools/reviewer/merge-gate.sh
fails=0
check(){ if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want rc=$2 got rc=$3"; fails=$((fails+1)); fi; }
gate(){ GATE_FACTS="$1" $G 99 >/dev/null 2>&1; echo $?; }

check "hold label always blocks"      1 "$(gate 'checks=pass labels=review-passed,hold impl_tier=1')"
check "green + reviewed merges"       0 "$(gate 'checks=pass labels=review-passed impl_tier=1')"
check "no CI blocks"                  2 "$(gate 'checks=none labels=review-passed impl_tier=1')"
check "red CI blocks"                 1 "$(gate 'checks=fail labels=review-passed impl_tier=1')"
check "pending CI waits"              2 "$(gate 'checks=pending labels=review-passed impl_tier=1')"
check "unreviewed waits"              2 "$(gate 'checks=pass labels= impl_tier=1')"
check "approved is the fast path"     0 "$(gate 'checks=none labels=approved impl_tier=1')"
check "no higher-tier reviewer holds" 2 "$(gate 'checks=pass labels=review-passed impl_tier=3')"

[ "$fails" -eq 0 ] || exit 1
EOF
chmod +x tests/pool/test_merge_gate.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/pool/test_merge_gate.sh`
Expected: several FAIL lines — the current gate ignores `GATE_FACTS`, requires `approved`, and treats `checks=none` as mergeable.

- [ ] **Step 3: Rewrite the gate**

```bash
cat > tools/reviewer/merge-gate.sh <<'EOF'
#!/usr/bin/env bash
# Decides whether a reviewed PR may be merged.
#
# The one irreversible step in the pool, so it is a separate readable file
# rather than prose in an agent prompt.
#   exit 0 -> merge
#   exit 1 -> hold: something is wrong; label review-blocked, a human must look
#   exit 2 -> clean but unsigned: label review-passed and walk away
#
# Set GATE_FACTS="checks=<pass|fail|pending|none> labels=<csv> impl_tier=<n>"
# to drive the decision directly; used by tests to exercise every row.
set -euo pipefail
pr="${1:?usage: merge-gate.sh <pr>}"
cd "$(dirname "$0")/../.."
SLUG="${POOL_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

if [ -n "${GATE_FACTS:-}" ]; then
  checks=$(printf '%s\n' $GATE_FACTS | sed -n 's/^checks=//p')
  labels=$(printf '%s\n' $GATE_FACTS | sed -n 's/^labels=//p')
  impl_tier=$(printf '%s\n' $GATE_FACTS | sed -n 's/^impl_tier=//p')
else
  labels=$(gh pr view "$pr" --repo "$SLUG" --json labels -q '[.labels[].name]|join(",")')
  impl_tier=$(printf '%s' "$labels" | tr ',' '\n' | sed -n 's/^impl-tier://p' | head -1)
  rollup=$(gh pr view "$pr" --repo "$SLUG" --json statusCheckRollup \
    -q '[.statusCheckRollup[]?.conclusion // .statusCheckRollup[]?.state] | @csv' 2>/dev/null || echo "")
  if   [ -z "$rollup" ];                          then checks="none"
  elif grep -qiE 'FAILURE|ERROR|TIMED_OUT' <<<"$rollup"; then checks="fail"
  elif grep -qiE 'PENDING|IN_PROGRESS|QUEUED' <<<"$rollup"; then checks="pending"
  else                                                 checks="pass"; fi
fi
impl_tier="${impl_tier:-1}"
has(){ printf '%s' ",$labels," | grep -q ",$1,"; }

# The emergency brake outranks everything, including the human fast-path.
if has hold; then echo "gate: hold label -> #$pr blocked" >&2; exit 1; fi

# Explicit human sign-off still merges, CI or no CI.
if has approved; then echo "gate: approved -> merge #$pr" >&2; exit 0; fi

if [ "$checks" = "fail" ]; then echo "gate: checks failed -> #$pr blocked" >&2; exit 1; fi

# Autonomy requires a real signal. An empty check set is not a green one:
# before CI existed, `none` merged everything, so it must now hold.
if [ "$checks" != "pass" ]; then
  echo "gate: checks=$checks -> #$pr awaits a green build" >&2; exit 2
fi

if ! has review-passed; then
  echo "gate: not reviewed -> #$pr awaits review" >&2; exit 2
fi

# No configuration may clear work at its own tier or below. If the roster
# offers nobody above this PR's builder, autonomy degrades to manual review
# rather than to self-approval.
if [ -z "$(./tools/pool/roster.sh reviewers-above "$impl_tier")" ]; then
  echo "gate: no reviewer above tier $impl_tier -> #$pr awaits sign-off" >&2; exit 2
fi

echo "gate: checks=pass reviewed tier>$impl_tier -> merge #$pr" >&2
exit 0
EOF
chmod +x tools/reviewer/merge-gate.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/pool/test_merge_gate.sh`
Expected: eight `ok -` lines, exit 0.

- [ ] **Step 5: Update the reviewer brief for the new exit-2 meaning**

In `tools/reviewer/REVIEWER.md`, the exit-2 branch currently says "only missing Jukka's approval". Replace that sentence with: "clean, but the gate is not satisfied yet — a green build, a review, or an eligible reviewer is missing. Run `mark-passed` and stop; the coordinator's merge pass will merge it once the gate clears."

- [ ] **Step 6: Commit**

```bash
git add tools/reviewer/merge-gate.sh tools/reviewer/REVIEWER.md tests/pool/test_merge_gate.sh
git commit -m "Merge autonomously on green CI plus a higher-tier review

checks=none now holds instead of merging: before CI existed an empty check
set was harmless, but under 'green CI + one reviewer' it would merge every
PR on no evidence. The approved label remains a fast-path and hold remains
an unconditional brake."
```

- [ ] **Step 7: Enable both pools**

```bash
# Review pool, created 2026-08-19:
orca automations edit --id 0915e1d0-fc7c-438c-aa8b-bce226273430 --enabled
# Implementation pool: take the id from Task 7 Step 4's JSON, or:
orca automations list
orca automations edit --id <id printed for "Epic implementation pool"> --enabled
```

Then watch the first autonomous cycle: `orca automations runs`.

---

## Notes for the executor

**Task 8 is the only irreversible one.** Tasks 1–7 leave the human `approved`
gate in place, so nothing merges unattended while you build. If CI is not
green and trustworthy when you reach Task 8, stop and say so rather than
loosening the gate to make progress.

**`ready.sh` returning something unexpected is a stop-the-line event**, not a
puzzle to work around. An over-permissive readiness check puts two agents on
one issue, or an implementer on unmerged foundations.
