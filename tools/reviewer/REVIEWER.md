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
     checks, or the branch no longer merges cleanly onto `main`.
     `gh pr edit <PR> --add-label review-blocked` and comment with the exact
     reason the gate printed.
   - **2** → the gate does not consider your review current, which means the
     head moved after you recorded it. If you pushed since step 6, re-run
     `mark-passed` and call the gate again. Otherwise comment and stop.
8. **Always**, success or failure: `./tools/reviewer/lease.sh release <PR>`.
9. Report back once:
   `orca orchestration send --type worker_done --subject "<PR> <merged|blocked>" \
      --body "<findings, fixes, what remains>" --task-id <task_id> \
      --dispatch-id <dispatch_id> --outcome <succeeded|failed> --json`

Do not touch any PR other than #<PR>. Do not force-push. Never remove
`review-blocked` — that label means a human owes an answer.

Your `mark-passed` is what merges this PR. The gate no longer waits for Jukka's
approval, so between your review and `main` there is no second pair of eyes.
Record a pass only for work you would defend under review yourself, and prefer
`review-blocked` over a pass you are unsure of. A pass you recorded on the
strength of a bare `godot --script` run is not a review — see step 4.
