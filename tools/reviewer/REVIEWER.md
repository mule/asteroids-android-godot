# Review PR #<PR>

You hold the review lease on PR #<PR> of this repo. Your worktree is already
checked out on that PR's head branch.

1. `gh pr view <PR> --json title,body,files` and read the linked issue for intent.
2. Review the diff against `main` with the `/code-review` skill at high effort.
   Judge it against the epic docs in `docs/superpowers/specs/` — a change that
   passes tests but contradicts the sector design is a finding.
3. Fix every finding you are confident about, directly on the PR branch.
   Leave a finding unfixed only when the fix is a design decision, not a defect.
4. Run every suite through `./tools/tests/run_godot_test.sh <suite.gd>`. If it
   fails, fix it. Never push a red branch, and never run the suites bare:
   `godot --script` exits 0 and prints `ALL TESTS PASSED` even when the script
   under test failed to compile, so a bare run cannot tell you anything. The
   runner is the only thing that turns a green suite into evidence.
5. Commit and push. Comment on the PR with what you found and what you changed.

   **If you pushed ANY commit to this PR — a one-line typo fix counts — stamp
   the PR with YOUR OWN roster tier before you go near the gate:**
   `gh pr edit <PR> --add-label impl-tier:<your tier from tools/pool/roster.tsv>`
   (remove any lower `impl-tier:` label the PR already carries, so it declares
   one tier, not two).

   This is not bookkeeping. The gate will only merge when the roster holds a
   reviewer of tier **strictly above** the PR's `impl-tier:<n>`, and a PR with
   no such label counts as tier 1. The moment you commit to the branch you are
   the author of that code, so leaving the label off would have you clearing
   your own work — the one thing the tier rule exists to prevent. Stamping your
   own tier makes `reviewers-above <your tier>` empty, the gate returns 2, and
   the PR correctly waits for a human or a higher tier. That is the intended
   outcome, not a failure of your review.

   **This is now enforced, not trusted.** `lease.sh claim` pinned the PR's head
   sha in `refs/reviewer-locks/pr-<PR>`; `mark-passed` compares that pin with
   the PR's current head, and when they differ — i.e. you pushed — it stamps
   the roster's review tier itself and refuses to record the pass if the label
   edit does not stick. Stamp it yourself anyway: the message you would
   otherwise leave the tooling to write is part of your review. And because
   `mark-passed` needs that pin, it also refuses to record a pass when you hold
   no lease on the PR.
6. Decide, and record the decision:
   - Clean, and you would defend every line of it →
     `./tools/reviewer/lease.sh mark-passed <PR>`. This records your pass
     against the **exact head sha** you reviewed, so push everything first.
     Do this before the gate — the gate reads this record, and a review you
     never recorded cannot clear it.
   - You left a finding unfixed because it needs a human decision →
     `gh pr edit <PR> --add-label review-blocked`, comment saying exactly what
     a human must decide, and skip to step 8. Do not mark it passed.
7. `./tools/reviewer/merge-gate.sh <PR>` and branch on its exit code:
   - **0** → `gh pr merge <PR> --squash --delete-branch`
   - **1** → the gate refuses on something you cannot clear yourself: red
     checks, a branch that no longer merges cleanly onto `main`, a malformed
     `impl-tier:` label, or the `hold` label.
     `gh pr edit <PR> --add-label review-blocked` and comment with the exact
     reason the gate printed — **except** when the reason it printed is the
     `hold` label. `hold` is an operator's deliberate brake, not a finding:
     comment and stop, do not add `review-blocked`, and never remove `hold`.
   - **2** → clean, but the gate is not satisfied yet — a green build, a
     review at the current head, or an eligible reviewer is missing. Read the
     line it printed:
     - *awaits a green build* → CI has not gone green on this head. Wait for
       the `tests` check and let the next pass pick the PR up. Absent checks
       are not passing checks, and the gate will not treat them as such.
     - *needs a re-review* → the head moved after you recorded your pass. If
       you pushed since step 6, re-run `mark-passed` and call the gate again.
     - *no roster reviewer above impl-tier:n* → nobody on the roster outranks
       whoever built this, which after step 5 usually means **you** did. This
       is the invariant working. Leave it for a human or a higher tier.
     In every case: comment with what the gate said and stop. Do not merge,
     and do not strip a label to make the gate happier.
8. **Always**, success or failure: `./tools/reviewer/lease.sh release <PR>`.
9. Report back once:
   `orca orchestration send --type worker_done --subject "<PR> <merged|blocked>" \
      --body "<findings, fixes, what remains>" --task-id <task_id> \
      --dispatch-id <dispatch_id> --outcome <succeeded|failed> --json`

Do not touch any PR other than #<PR>. Do not force-push. Never remove
`review-blocked` — that label means a human owes an answer. Never remove
`hold`, and never remove or lower an `impl-tier:` label: both exist to stop
merges, so removing one is indistinguishable from merging something nobody
cleared.

Your `mark-passed` is what merges this PR. The gate no longer waits for Jukka's
approval, so between your review and `main` there is no second pair of eyes.
Record a pass only for work you would defend under review yourself, and prefer
`review-blocked` over a pass you are unsure of. A pass you recorded on the
strength of a bare `godot --script` run is not a review — see step 4.
