# global agent instructions

- Never use the em dash "—". Use plain dash "-" instead
- When writing commit messages, NEVER auto-add your agent name as co-author
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.
- When creating, switching, or removing git worktrees, use the `wt` CLI (worktrunk) instead of raw `git worktree` commands.

## Delegation Workflow
Talk to me through this session only - side workers are visible in their
own herdr tabs, but I don't expect to talk to them directly; you relay
everything.

When a task looks like it warrants a worker (touches more than one file,
or is likely more than a few minutes of focused work), propose it and
wait for my go-ahead before creating anything - do not spin up a worker
on your own. Trivial, single-file, quick asks: just handle them directly,
no need to ask.

**Delegate** (only after I say yes)
1. `wt switch --create <branch>` - always in its own worktree, never work
   on a delegated task directly. `agents-init`'s wiring runs automatically.
2. `herdr tab create --cwd <worktree_path> --label <branch>` - one new
   tab per worker. Note the `root_pane` id from the result.
3. `herdr pane run <pane_id> "claude '<task>'"` in that same pane - a
   complete, self-contained task description; the worker starts cold,
   with no access to this conversation.

**Wait**
4. Check current status first (`herdr agent list`, find the pane) - if
   not already `idle`, then `herdr wait agent-status <pane_id> --status
   idle --timeout <ms>`. Don't block your ability to keep talking to me
   in the meantime.

**Surface for Review**
5. Once idle: in that same tab/pane, run `hunk diff`.
6. Tell me explicitly which tab has it ready - don't wait to be asked.

**Relay Feedback**
7. Wait for my verdict.
8. If fixing is needed: `herdr pane run <pane_id> "<feedback>"` (typed as
   a new message into the worker's session), then return to step 4.
9. If good: proceed per this project's actual PR/merge policy - read it
   from elsewhere in this file, or ask if unclear.

**Guardrails**
- Never skip the review step (5-6), even if the worker reports success.
- Never merge, push, or open a PR without my explicit confirmation in
  this session.
- Only run herdr control commands when `HERDR_ENV=1` is actually set -
  refuse and say so otherwise.
