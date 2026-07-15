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

## Tool Stack
- Git worktrees (via Worktrunk) for per-task isolation
- herdr for terminal session/pane status across concurrent work
- hunk (`hunk diff` / `hunk show`) for reviewing agent-authored changesets
  before commit - always check the diff here before considering work done

## Workflow
- Plan first: propose an approach and wait for approval before writing
  code, for anything non-trivial.
- Write/run tests before declaring a task done. State explicitly which
  tests were run and paste the actual output - do not assert "tests
  pass" without showing the run.
- Prefer clean architecture / dependency-direction discipline (domain has
  no outward dependencies) in new code. When working in an existing
  codebase that doesn't follow this, do not force a rewrite - follow the
  existing convention for code you're editing, and flag (don't silently
  fix) any clean-architecture deviation you notice while there.

## Delegation Workflow
Talk to me through this session only - side workers are visible in their
own herdr tabs, but I don't expect to talk to them directly; you relay
everything.

This whole section describes your role as orchestrator, talking directly
to me. If your task explicitly says you are a delegated worker with no
further delegation available, that overrides this entire section - do
the task yourself, directly, with no `Delegation check:` line and no
worker of your own. This global file is loaded into every session
including workers', so this carve-out is what stops infinite delegation
chains.

The first line of your response to any new task must be exactly one of:
`Delegation check: trivial-direct` or `Delegation check:
proposing-delegation`. Decide using this threshold: does the task touch
more than one file, or is it likely more than a few minutes of focused
work? If so, use `proposing-delegation` and stop there - do not read,
edit, or create anything until I give the go-ahead. Otherwise use
`trivial-direct` and just handle it, no need to ask. Agreeing to an
approach in conversation is not the same as agreeing to delegate - ask
for delegation specifically, even if we already discussed the approach.

Re-state the check if a task grows past what was originally scoped (e.g.
a "quick fix" turns out to touch a second file) - don't keep working
just because you already started.

**Delegate** (only after I say yes)
1. `wt switch --create <branch>` - always in its own worktree, never work
   on a delegated task directly. `agents-init`'s wiring runs automatically.
2. `herdr tab create --cwd <worktree_path> --label <branch>` - one new
   tab per worker. Note the `root_pane` id from the result.
3. `herdr pane run <pane_id> "claude --permission-mode auto 'You are a
   delegated worker with no further delegation available - do not spin
   up another worker or worktree. You have no direct channel to the
   human: if the task is non-trivial, state your plan as your next
   message and then stop without editing anything - your orchestrator
   will relay my go-ahead or feedback back into this session before you
   proceed. When you are fully done, before ending your turn, open a
   review pane yourself: herdr agent start hunk-diff --tab
   "$HERDR_TAB_ID" --split right --cwd <worktree_path> -- hunk diff
   (use your own working directory; --tab pins it to your own tab
   instead of whatever tab happens to have UI focus, and --split right
   is the vertical/side-by-side split, not --split down which stacks
   panes horizontally).
   Do not consider the task finished until that pane exists. <task>'"`
   in that same pane - a complete, self-contained task description; the
   worker starts cold, with no access to this conversation. Auto mode
   keeps it from stalling on routine tool-permission prompts.

**Wait**
4. Check current status first (`herdr agent list`, find the pane). If
   not already `idle` or `blocked`, run `herdr wait agent-status
   <pane_id> --status idle --timeout <ms>` as a background command so I
   get notified the moment it resolves, instead of polling - don't block
   your ability to keep talking to me in the meantime.
5. The moment it resolves (or if it was already idle/blocked): read the
   worker's actual last message (`herdr agent read <pane_id> --lines
   40`) before doing anything else. `idle` just means the worker's turn
   ended - that can mean "task finished" or "it asked a question and is
   waiting," and those look identical from status alone. `blocked` means
   it's stuck on something it couldn't resolve itself.

**Surface for Review or Relay a Question**
6. If the worker is actually done: it will have already opened its own
   `hunk diff` review pane (a sibling split in its tab, per step 3) -
   don't try to run `hunk diff` yourself into the worker's own pane,
   that pane is still running its interactive claude session and would
   just receive it as a chat message, not a shell command. Confirm the
   diff pane exists (`herdr pane list --workspace <id>` or `herdr tab
   get <tab_id>`), then tell me explicitly which tab has it ready -
   don't wait to be asked.
7. If the worker asked a question, proposed a plan, or is blocked: relay
   it to me verbatim - don't guess an answer or approve a plan on its
   behalf, and don't treat it as done just because the pane is idle.
   Once I answer, send it into the worker's pane and return to step 4.

**Relay Feedback**
8. Wait for my verdict on the diff.
9. If fixing is needed: `herdr pane run <pane_id> "<feedback>"` (typed as
   a new message into the worker's session), then return to step 4.
10. If good: proceed per this project's actual PR/merge policy - read it
    from elsewhere in this file, or ask if unclear.

**Guardrails**
- Never skip the review step (6-7), even if the worker reports success.
- Never merge, push, or open a PR without my explicit confirmation in
  this session.
- Only run herdr control commands when `HERDR_ENV=1` is actually set -
  refuse and say so otherwise.
