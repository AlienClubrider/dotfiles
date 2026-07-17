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
2. `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd
   <worktree_path> --label <branch>` - one new tab per worker, pinned to
   your own workspace. Omitting `--workspace` falls back to whatever
   workspace currently has UI focus, which may belong to someone else's
   orchestrator session - the same failure mode step 3's `--tab
   "$HERDR_TAB_ID"` already guards against for tab focus. Note the
   `root_pane` id from the result.
3. If you and I already discussed and settled on a concrete approach
   before delegating, carry that plan into `<task>` verbatim, labeled
   `Plan: ...`, so the worker does not have to rediscover it. Either
   way, the worker executes directly, without pausing to propose its
   own plan and wait - delegation only happens after I have already
   said yes to the task's scope (per the Workflow section above), so a
   worker-side re-approval of that same scope is redundant and wastes a
   round trip. It only pauses if its own investigation shows the task
   needs to go beyond the scope I approved, or if it hits a genuine
   blocker it cannot resolve itself.
   Send this into that same pane as a self-contained task description -
   the worker starts cold, with no access to this conversation:
   `claude --permission-mode auto 'You are a delegated worker with no
   further delegation available - do not spin up another worker or
   worktree. You have no direct channel to the human: execute the task
   directly, investigating as needed - do not pause to propose a plan
   and wait, the task's scope was already approved before you were
   delegated. Only stop and wait, instead of proceeding, if your
   investigation shows the task needs to go beyond that approved scope,
   or if you hit a genuine blocker you cannot resolve yourself; say
   what you found, your orchestrator will relay a decision back into
   this session before you proceed further. When you are fully done,
   before ending your turn, open a review pane yourself: herdr agent
   start hunk-diff --tab "$HERDR_TAB_ID" --split right --cwd
   <worktree_path> -- hunk diff (use your own working directory; --tab
   pins it to your own tab instead of whatever tab happens to have UI
   focus, and --split right is the vertical/side-by-side split, not
   --split down which stacks panes horizontally). Do not consider the
   task finished until that pane exists. <task>'`. Auto mode keeps it
   from stalling on routine tool-permission prompts. Never fold a
   commit instruction into `<task>` - the review pane opens with `hunk
   diff`, which shows only uncommitted working-tree changes, so
   committing first leaves it empty. Committing (and merging) belongs
   after my verdict, in steps 9-10.

   Send it as two explicit steps, never as a single `herdr pane run`
   call - confirmed by direct reproduction, a prompt this long (the
   template above plus a real task description routinely runs well
   over 1000 characters as one quoted argument) reliably races the
   target shell's own rendering of the pasted text: `pane run`'s
   type-then-Enter happens with no settle time, the shell is still
   redrawing the long pasted line when the Enter arrives, and the Enter
   gets swallowed instead of submitting - the text sits there typed but
   unsent, and the pane never goes `working`. A single naive follow-up
   `send-keys Enter` does not reliably fix this either - it's as likely
   to insert another literal newline into the stuck buffer as it is to
   submit it. What does work reliably:
   a. `herdr pane send-text <pane_id> "<the full command above>"` -
      types/pastes the text only, does not submit it.
   b. Wait about 2 seconds for the target shell to finish rendering the
      pasted text before doing anything else.
   c. `herdr pane send-keys <pane_id> enter` - submits it.
   d. Verify it actually went through: `herdr pane read <pane_id>
      --source recent --lines 40`. A fresh shell prompt, claude's
      startup panel, or a thinking/working indicator means it
      submitted; the same typed text still sitting at the bottom with
      no prompt below it means it didn't. If it didn't, send `herdr
      pane send-keys <pane_id> ctrl+c` to clear the wedged buffer, then
      repeat from (a).

**Wait**
4. Check current status first (`herdr agent list`, find the pane). If
   not already `idle`, `blocked`, or `done`, run three background waits
   - `herdr wait agent-status <pane_id> --status idle --timeout <ms>`,
   the same with `--status blocked`, and the same with `--status done`
   (`--status` takes exactly one value per invocation; passing it twice
   on one call silently keeps only the last one given) - so I get
   notified the moment any of them resolves, instead of polling. Stop
   the other two once one fires. Don't block your ability to keep
   talking to me in the meantime.
5. The moment one resolves (or if it was already idle/blocked/done): read the
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
9. If fixing is needed: send `<feedback>` into the worker's session the
   same two-step, settle-then-verify way as step 3's send - short
   feedback strings are less likely to hit the race than the full
   worker-launch template, but not immune to it, so use the same
   reliable path rather than the single-shot `herdr pane run` for
   consistency. Then return to step 4.
10. If good: ask what should happen next if I haven't already said
    (merge to a target branch, open a draft PR, rebase only, or
    something else) - never assume a default. Relay that instruction
    into the worker's pane the same way as feedback - it already has the
    worktree, branch, and full context, so it does this itself, not you.
    For a merge, tell it to use `wt merge` (never raw git) - it squashes,
    rebases, runs pre-merge hooks as validation, fast-forwards into the
    target branch, and removes its own worktree and branch automatically
    as part of the same command. Then return to step 4 and wait for it
    like any other delegated step - it may hit its own blockers (merge
    conflicts, failing pre-merge hooks) that need relaying back to me.

**Clean Up**
11. Once the follow-up work is confirmed done and I've approved it: if
    the worker already ran `wt merge` (or anything else that
    self-removes the worktree), the worktree and branch are already
    gone - just close the herdr tab (`herdr tab close <tab_id>`). If the
    worktree is still around (e.g. a draft-PR flow that intentionally
    keeps it open), remove it yourself first with `wt remove <branch>`
    (never raw `git worktree`), then close the tab. My approval of the
    follow-up work is also approval to clean up - no separate check-in
    needed for this step.

**Guardrails**
- Never skip the review step (6-7), even if the worker reports success.
- Never merge, push, or open a PR without my explicit confirmation in
  this session.
- Only run herdr control commands when `HERDR_ENV=1` is actually set -
  refuse and say so otherwise.
