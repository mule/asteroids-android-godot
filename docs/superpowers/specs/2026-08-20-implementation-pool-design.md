# Design: An agent pool that implements the epic

Date: 2026-08-20
Status: Approved for planning
Epic: [#43](https://github.com/mule/asteroids-android-godot/issues/43)
Follows: [PR reviewer pool](../../../tools/reviewer/COORDINATOR.md) (`743ee0e`)

## Goal

Let the scrolling-sector epic advance without a human typing. A scheduled pool
of agents picks up child issues whose dependencies have merged, implements
them, and opens pull requests. The existing review pool reviews those PRs, and
— once the signal it depends on is trustworthy — merges them, which unblocks
the next issues in the graph.

The two pools together form a closed loop: implement → PR → review → merge →
unblock. This document specifies the implementation half and the changes the
review half needs to close the loop safely.

## Why now

The review pool proved the mechanics on 2026-08-19: a scheduled Orca
automation claimed PR #60 under a GitHub-arbitrated lock, dispatched a worker
to its own worktree, found a real regression, pushed two fixes with tests, and
released cleanly in 11½ minutes. Everything in that run generalises except the
domain logic.

The epic has 15 unimplemented child issues (#45–#59) whose bodies already
carry a machine-readable dependency graph.

## Current state

- `tools/reviewer/` holds a working pool: `lease.sh`, `precheck.sh`,
  `merge-gate.sh`, and two agent briefs.
- Mutual exclusion is a git ref under `refs/reviewer-locks/`. Ref creation is
  an atomic compare-and-swap on GitHub; the first agent wins, later agents get
  HTTP 422.
- `refs/reviewer-passed/pr-N` pins the sha a reviewer cleared, so unchanged
  PRs are not re-reviewed and new commits re-open the queue.
- The merge gate requires a human `approved` label, because agent PRs and
  agent reviews share the `mule` account and GitHub forbids self-approval.
- Every child issue body ends with a `## Dependencies` section reading
  `Requires #44, #45.`
- Agents configured on this Orca host: `antigravity`, `claude`, `codex`,
  `gemini`, `grok`.

## Design principles

**GitHub holds all shared state.** Automation runs are ephemeral worktrees
with no memory between them. Anything a coordinator needs to know must be
readable from refs, labels, and issue bodies.

**One mutex implementation.** The lock is the only thing standing between two
agents and the same task. It exists once, and both pools call it.

**Nothing reviews its own work.** Enforced by tier, not by convention.

**Fail closed.** Every ambiguity resolves toward "leave it for a human".

## Architecture

### Shared lock core — `tools/pool/lock.sh`

The primitive lifted out of `lease.sh`, made namespace-generic.

```
lock.sh claim   <ns> <key> <sha>   # atomic; non-zero if another agent holds it
lock.sh release <ns> <key>
lock.sh held    <ns>               # keys currently locked
lock.sh stamp   <key>              # ISO time of the newest lease comment
lock.sh sweep   <ns> <ttl-min> <live-keys...>
```

Namespaces are disjoint: `refs/reviewer-locks/pr-N` and
`refs/implementer-locks/issue-N`. A PR and its originating issue lock
independently.

Stale detection reads the newest `<!-- lease -->` marker comment. GitHub
serves PR and issue comments from the same `issues/N/comments` endpoint, so
one implementation covers both.

`sweep` also garbage-collects refs whose key is no longer live, keeping the
namespace the size of the open queue rather than the repo's history.

### Readiness — `tools/implementer/ready.sh`

An issue is claimable when **all** hold:

1. It is open.
2. Its body opens with `Parent epic: #43`. This is the only membership test;
   issue numbers are not assumed to be contiguous.
3. It carries neither `impl-blocked` nor `hold`.
4. No open PR references it.
5. It is not locked.
6. Every issue named in its `## Dependencies` → `Requires #N` line is CLOSED.

Rule 6 is strict by decision: implementers always build on merged code on
`main`. Parallelism comes from the width of the dependency graph, not from
speculating on unmerged branches. When #44 merges, `{45, 47, 48, 50}` open at
once.

### Roster and routing — `tools/pool/roster.tsv`

```
# role       agent        model      effort  tier
implement    antigravity  3.7-flash  -       1
implement    claude       opus       high    2
implement    codex        gpt-5.5    high    2
review       claude       opus       max     3
```

Routing an issue to an implementer:

- An `agent:<id>` label on the issue selects that agent explicitly.
- Otherwise the lowest-tier `implement` row takes it.

In practice: antigravity handles unlabelled issues; issues labelled
`agent:claude` go to opus. The human marks which work is hard.

**The tier invariant:** a PR may only be reviewed by a roster row whose tier is
strictly greater than the tier that built it. The implementer stamps
`impl-tier:<n>` on its PR; the review pool filters its roster to rows above
that number. Opus-at-`max` reviewing opus-at-`high` satisfies this; opus
reviewing its own tier does not.

Orca's `worker-start --model/--effort` supports Claude, Codex, and Cursor
only. Antigravity's model is therefore *declared* in the roster and configured
on antigravity's own side, not enforced by Orca. The roster row documents
intent; it does not guarantee it.

That list is about pinning a *model*, and is not the list of agents the roster
may name. `worker-start --agent` validates against the agents **configured in
Orca** — one hook apiece under `~/.orca/agent-hooks/` — and rejects anything
else with `agent_unconfigured`. An agent that is merely a binary on PATH does
not qualify. A row naming one costs a claim on every scheduled run: the
coordinator locks the issue, the launch fails, and the issue comes back
untouched — and because `MAX_PARALLEL` counts rows, the same row inflates the
fleet budget past what can actually start. `tests/pool/test_roster.sh` enforces
this, so the roster grows only after the hook does.

### Concurrency

`MAX_PARALLEL` is the number of `implement` rows in the roster — 3 today
(antigravity, claude, codex), and it grows only when a fourth agent is
configured in Orca, not when a fourth is merely installed. A coordinator
claims at most `MAX_PARALLEL - len(held(implementer-locks))` issues. The
subtraction matters: the lock prevents two agents taking the same *issue*, not
a second scheduled run doubling the *fleet* while the first is still working.

### Cadence

The implementer automation runs **hourly**, against the review pool's 30
minutes. Implementations take tens of minutes, so a tighter interval only
produces runs that find their own predecessors still working. As with the
review pool, a precheck exits non-zero when nothing is ready, so an idle epic
costs no agent sessions.

### The implementer's contract — `tools/implementer/IMPLEMENTER.md`

Given a locked issue, a worker in a fresh worktree branched from `main`:

1. Reads the issue and the epic design docs for intent.
2. Implements against the issue's stated interfaces and acceptance criteria,
   test-first where the issue names tests.
3. Runs the full suite. Never pushes a red branch.
4. Opens a PR referencing the issue, labelled `impl-tier:<n>`.
5. Releases the lock, always.
6. Reports `worker_done` with outcome and files touched.

**Give-up path.** When tests will not pass, the issue is ambiguous, or 60
minutes have passed since the lock was taken: push what exists as a **draft** PR, label the issue
`impl-blocked` with a comment naming exactly what stopped it, release the
lock. The issue leaves the pool until a human clears the label. Draft PRs are
already invisible to the review pool, which filters `select(.isDraft | not)`.

## The merge gate, flipped

Autonomy inverts the current logic. Under "green CI + one reviewer",
`checks=none` must **fail**, or every PR merges on an empty check set.

```
hold label                              => never merge
checks == pass AND review-passed        => merge
approved label                          => merge   (human fast-path)
no reviewer of higher tier available    => require approved
otherwise                               => hold for sign-off
```

The `approved` fast-path and the `hold` brake both remain. Autonomy degrades
to manual review; it never degrades to self-approval.

## Prerequisites

Autonomy is worth exactly as much as the signal it trusts, and one of them is
currently broken.

1. **Fix the test harness.** `tests/*.gd` print `ALL TESTS PASSED` and exit 0
   even when the script under test fails to compile — found as Finding 6 of
   the #60 review. Until fixed, green CI is a lie and auto-merge ships broken
   code with a passing badge.
2. **Add `.github/workflows/ci.yml`** running headless Godot plus the suites.
   The #60 review demonstrated the technique.

Only then does flipping the gate become safe.

## Build order

1. Fix the test harness exit codes.
2. Add CI.
3. Extract `tools/pool/lock.sh`; migrate the review pool onto it, unchanged in
   behaviour.
4. Build the implementer pool; run it manually against one issue.
5. Flip the merge gate to autonomous.

Autonomy lands last, deliberately. Steps 1–4 leave the human gate in place.

## Testing strategy

The pools are shell plus agent prompts, so testing is behavioural:

- **Lock:** two concurrent `claim` calls on one key; exactly one wins. Already
  demonstrated on PR #60.
- **Readiness:** an issue with an open dependency is absent from `ready`; it
  appears when that dependency closes. Verifiable today against #45/#44.
- **Idempotence:** a second run with no new work claims nothing and comments
  nothing.
- **Give-up:** a deliberately impossible issue produces a draft PR, an
  `impl-blocked` label, and a released lock.
- **Tier invariant:** a PR labelled `impl-tier:3` finds no eligible reviewer
  and falls back to requiring `approved`.
- **Merge gate:** each row of the table above, exercised against a real PR.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Green CI that is not green | Fix the harness before CI is trusted; prerequisite 1 |
| Agents run with bypass permissions, unattended | Gate bounds what reaches `main`, not what runs; keep the roster small and the cadence visible |
| Two runs overlapping double the fleet | Concurrency accounts for held locks, not just per-run count |
| An implementer's lock outlives a crashed agent | TTL sweep returns the issue to the pool |
| Implementer builds on a stale `main` | Worktree branches from `main` at claim time; strict readiness means deps are already merged |
| Epic stalls silently | `impl-blocked` and `hold` are both visible labels; coordinator reports each run |

## Out of scope

- Any pool acting on repositories other than this one.
- Implementers merging their own work, under any condition.
- Speculative implementation on unmerged dependency branches.
- Automatic issue creation or epic re-planning.
