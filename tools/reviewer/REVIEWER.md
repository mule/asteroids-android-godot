# Review PR #<PR>

You hold the review lease on PR #<PR> of this repo. Your worktree is already
checked out on that PR's head branch.

1. `gh pr view <PR> --json title,body,files` and read the linked issue for intent.
2. Review the diff against `main` with the `/code-review` skill at high effort.
   Judge it against the epic docs in `docs/superpowers/specs/` — a change that
   passes tests but contradicts the sector design is a finding.
3. Fix every finding you are confident about, directly on the PR branch.
   Leave a finding unfixed only when the fix is a design decision, not a defect.
4. Run the Godot test suite. If it fails, fix it. Never push a red branch.
5. Commit and push. Comment on the PR with what you found and what you changed.
6. `./tools/reviewer/merge-gate.sh <PR>` and branch on its exit code:
   - **0** → `gh pr merge <PR> --squash --delete-branch`
   - **2** → clean, only missing Jukka's approval.
     `./tools/reviewer/lease.sh mark-passed <PR>`, comment with a short summary
     so the approval is a quick read, and stop. Do **not** add review-blocked —
     that would take the PR out of the pool for good.
   - **1** → something is actually wrong. `gh pr edit <PR> --add-label review-blocked`
     and comment saying exactly what a human needs to decide.
7. **Always**, success or failure: `./tools/reviewer/lease.sh release <PR>`.
8. Report back once:
   `orca orchestration send --type worker_done --subject "<PR> <merged|blocked>" \
      --body "<findings, fixes, what remains>" --task-id <task_id> \
      --dispatch-id <dispatch_id> --outcome <succeeded|failed> --json`

Do not touch any PR other than #<PR>. Do not force-push. Never add or remove the
`approved` label and never remove `review-blocked` — `approved` is Jukka's
sign-off and the only thing standing between your own edits and a merge.
