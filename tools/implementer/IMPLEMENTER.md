# Implement issue #<ISSUE>

You hold the implementation lease on issue #<ISSUE> of
`mule/asteroids-android-godot`. Your worktree is a fresh branch off `main`.
Your roster tier is **<TIER>**.

The lease is a git ref, `refs/implementer-locks/issue-<ISSUE>`. It is the only
thing that grants you the right to implement this issue, and **you must release
it before you finish, whatever the outcome** (step 8).

Work through this file top to bottom. Run every command from the repository
root of your worktree.

---

## Precedence: the script is the policy

Where this brief's description of a script disagrees with the script itself,
**the script wins**. This file is a copy of the policy; the scripts under
`tools/` *are* the policy. If a command here fails in a way this file does not
describe, read the script, do what the script actually does, and say so in your
report. Never guess, and never work around a script by doing its job by hand.

---

## Step 0 — Start the clock

```bash
export POOL_REPO=mule/asteroids-android-godot
LEASE_START=$(date -u +%s)   # remember this; you need it at step 7
date -u
```

**You have 60 minutes from now.** That deadline is a hard rule, not a
suggestion — see step 7.

---

## Step 1 — Read the work

```bash
gh issue view <ISSUE> --repo mule/asteroids-android-godot
```

Then read the epic design in `docs/superpowers/specs/` and, where the issue
links one, the referenced plan under `docs/superpowers/plans/`.

The issue's `## Interfaces produced` section is a **contract that later issues
depend on**. Match those names, types and signatures exactly. Renaming or
"improving" one silently breaks issues that are already scheduled against it.

Note the issue's `## Dependencies` section, but **do not edit it** — see the
prohibitions at the end.

---

## Step 2 — Implement

Implement against the issue's `## Acceptance criteria`. Where the issue names a
test file, write that test first, run it, watch it fail, and only then write the
implementation.

Stay inside the files the issue's `## Files` section names. If you must touch a
file outside that list, do it, and say so explicitly in your report.

---

## Step 3 — Run the Godot suites (the only correct way)

```bash
for t in tests/test_*.gd; do ./tools/tests/run_godot_test.sh "$t" 300; done
```

`run_godot_test.sh <script> [timeout-seconds]` imports the project first, runs
the script under a hard timeout, and fails on a timeout or on any engine-level
error line even when the script exited 0.

**A bare `godot --headless --script <file>` run is not acceptable evidence, and
you must never substitute one.** A script whose dependency fails to compile
never reaches `quit()` and hangs forever instead of failing; a script that
prints `SCRIPT ERROR` can still exit 0 and print `ALL TESTS PASSED`. The runner
is the only thing that turns a green suite into evidence.

**This overrides the issue body.** Several epic issues carry a `## Verification`
section containing bare `godot --headless --path . --script ...` lines. Treat
those as a list of *which* suites matter, and run each one through
`./tools/tests/run_godot_test.sh` instead. Do not copy the bare invocations.

If you changed anything under `tools/`, also run the matching shell suite:

```bash
for t in tests/pool/test_*.sh; do "$t" || echo "FAILED: $t"; done
```

**Never push a red branch.**

---

## Step 4 — Run the Python suite, or report that you could not

```bash
python3 -m pytest tests/asset_pipeline -q; echo "pytest rc=$?"
```

pytest is a **CI-provided dependency, not a local one**, and it is not
installed on the pool's current host. If the command fails with
`No module named pytest` (or pytest is otherwise unavailable):

- **Report that fact and continue.** Say so plainly in your PR body and in your
  step 9 report: "python suite not run locally: pytest unavailable; CI runs it
  on the PR."
- This is **not** a red suite and it is **not** grounds for the give-up path.
  CI runs it against the PR regardless, so the signal is not lost.

If pytest *is* available and the suite **fails**, that is a genuine red suite:
fix it, or take the give-up path.

---

## Step 5 — Commit and push

Commit your work and push your branch. Never force-push. Never push to `main`.

---

## Step 6 — Open the PR

```bash
gh pr create \
  --repo mule/asteroids-android-godot \
  --base main \
  --title "<short description>" \
  --body "$(cat <<'BODY'
Closes #<ISSUE>

<what you built, how you verified it, anything you deliberately left out,
and whether the python suite ran locally>
BODY
)" \
  --label "impl-tier:<TIER>"
```

The body **must** contain the literal line `Closes #<ISSUE>`.

**The `impl-tier:<TIER>` label is mandatory.** `<TIER>` is exactly the tier
`route.sh` returned for this issue and that this brief was stamped with — do
not compute it yourself and do not change it. The review pool reads this label
to pick a reviewer of *strictly higher* tier. **An unlabelled PR defaults to
tier 1 at the merge gate, which lets a lower-tier reviewer clear work it is not
qualified to clear.** Omitting it is a correctness failure, not a cosmetic one.

If `gh pr create` rejects the label, add it immediately afterwards and verify:

```bash
gh pr edit <PR> --repo mule/asteroids-android-godot --add-label "impl-tier:<TIER>"
gh pr view <PR> --repo mule/asteroids-android-godot --json labels -q '[.labels[].name]'
```

Do not consider the PR done until that list contains `impl-tier:<TIER>`.

---

## Step 7 — The give-up path (hard 60-minute deadline)

Take this path if **any** of the following is true:

- The Godot suites will not pass and you cannot fix them.
- The issue is ambiguous, contradicts the epic design, or its
  `## Interfaces produced` cannot be satisfied as written.
- **60 minutes have elapsed since `LEASE_START` in step 0.** Check it:

  ```bash
  echo "elapsed_minutes=$(( ( $(date -u +%s) - LEASE_START ) / 60 ))"
  ```

  At 60 minutes you stop, whatever state you are in. **Do not grind past the
  deadline.** The lease TTL is 90 minutes; the 30-minute margin exists so you
  hand the issue back cleanly instead of having it swept out from under you.

Note that a missing local pytest (step 4) is explicitly **not** a give-up
condition.

The give-up path, in order:

1. Push what you have and open it as a **draft** PR:

   ```bash
   gh pr create --repo mule/asteroids-android-godot --base main --draft \
     --title "<short description> (WIP)" \
     --body "Refs #<ISSUE> — partial work, see the issue comment." \
     --label "impl-tier:<TIER>"
   ```

   Draft PRs are invisible to the review pool, so partial work is safe to
   leave. Use `Refs #<ISSUE>`, not `Closes`, on a draft.

   If you have nothing worth pushing, skip the draft PR entirely.

2. Label and explain on the issue:

   ```bash
   gh issue edit <ISSUE> --repo mule/asteroids-android-godot --add-label impl-blocked
   gh issue comment <ISSUE> --repo mule/asteroids-android-godot --body \
     "<exactly what stopped you, exactly what a human must decide, and where the partial work is>"
   ```

   The comment must name a decision, not a feeling. `impl-blocked` removes the
   issue from the claimable queue until a human clears it.

3. Continue to step 8, then report with `--outcome failed`.

---

## Step 8 — Release the lease. Always.

```bash
./tools/pool/lock.sh release implementer-locks issue-<ISSUE>
```

**Run this unconditionally — on success, on failure, on give-up, on anything.**
It is the last thing you do before reporting, and it has no failure branch:
`release` is idempotent and swallows its own errors.

A held lock with no live worker stalls the pool silently until the 90-minute
sweep breaks it. Every minute between your exit and that sweep is a worker slot
nobody can use.

Verify it is gone:

```bash
./tools/pool/lock.sh held implementer-locks
```

`issue-<ISSUE>` must not appear. (Non-zero exit here means the API call failed,
not that the lock is still held — retry once, then move on.)

---

## Step 9 — Report exactly once

```bash
orca orchestration send --type worker_done \
  --subject "<ISSUE> <opened|blocked>" \
  --body "<what you built, how you verified it, whether the python suite ran locally, what remains>" \
  --task-id <task_id> \
  --dispatch-id <dispatch_id> \
  --outcome <succeeded|failed> \
  --json
```

Use the `task_id` and `dispatch_id` Orca injected into your prompt. `--outcome`
is required and must be `succeeded` or `failed` — never encode failure only in
prose. Send this once; do not follow it with `task-update`.

---

## Prohibitions — absolute

- **Do not touch any issue other than #<ISSUE>** — no labels, no comments, no
  edits, no closing. Not even to note something you noticed.
- **Do not edit any issue's `## Dependencies` section**, including this issue's.
  An agent that can edit dependencies can unblock itself, which defeats the
  entire scheduler. If a dependency looks wrong, say so in your report and leave
  it alone.
- **Do not merge anything**, including your own PR.
- **Do not add the `approved` label** to any issue or PR, for any reason. It is
  a human override that skips the merge gate's sha check. Only Jukka adds it.
- **Do not remove the `review-blocked` label** from anything. It means a human
  owes an answer.
- **Do not force-push.** Do not push to `main`. Do not rewrite published history.
- **Do not claim, release, or otherwise touch a lock for any issue other than
  #<ISSUE>**, and do not break another agent's lock.
- **Do not review your own PR**, add `review-passed`, or run
  `tools/reviewer/lease.sh mark-passed`.
- Do not run any suite bare instead of through
  `./tools/tests/run_godot_test.sh`.
