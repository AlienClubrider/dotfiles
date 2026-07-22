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

**Delegation state directory**
Keep a `.claude/delegation/` directory at the root of your own working
checkout (never inside a worker's worktree - that gets torn down on
merge). Add it to `.git/info/exclude` the same way `agents-init` already
excludes `AGENTS.md`/`CLAUDE.md`, so it never gets staged or committed.
It holds:
- `index.md` - one line per active or recently-finished worker, the
  roster you rebuild everything else from.
- `<branch>.md` - one plan/status file per worker, named after its
  branch.

Only you write to `index.md`, and only you edit a worker's `<branch>.md`
header (its `status:` field) once that worker is idle/blocked/done -
while a worker is live, its own `<branch>.md` is its single-writer
scratchpad, avoiding any concurrent-write race. These files are a
durable checkpoint, not a replacement for live status: always reconcile
them against `herdr agent list` / `herdr agent read` before acting on
them, especially right after a context clear - a file can lag what a
worker's pane is actually doing.

**Delegate** (only after I say yes)
1. Invoke the `delegate` skill (`/delegate <branch>`), with the Goal
   paragraph and Plan checklist already settled from our conversation
   ready to hand it - verbatim, if you and I already discussed and
   agreed on a concrete approach, so the worker doesn't have to
   rediscover it. The skill mechanizes everything that used to be spelled
   out here as five separate steps and a 1000-character inline template:
   creating the worktree (`wt switch --create`), spawning the herdr tab
   (`herdr-spawn-tab`, which finds-or-creates your project's own herdr
   workspace by a stable label instead of assuming `--workspace` is set
   correctly - the failure mode that used to land a tab in whatever
   workspace had UI focus), writing `.claude/delegation/<branch>.md` and
   appending `.claude/delegation/index.md`, and composing and sending the
   worker-launch instructions via `herdr-send-verified` (a single
   verified call that replaces the old manual send-text/sleep/send-keys/
   verify/retry dance for the paste-race that used to swallow Enter on
   long task text). See `.claude/skills/delegate/SKILL.md` for exactly
   what it does. The worker executes directly once launched, without
   pausing to propose its own plan and wait - delegation only happens
   after I have already said yes to the task's scope (per the Workflow
   section above), and its plan is already written into
   `.claude/delegation/<branch>.md`, so a worker-side re-approval of that
   same scope is redundant and wastes a round trip. It only pauses if its
   own investigation shows the task needs to go beyond the scope I
   approved, or if it hits a genuine blocker it cannot resolve itself.

**Wait**
2. Check current status first (`herdr agent list`, find the pane). If
   not already `idle`, `blocked`, or `done`, run `herdr-wait-any
   <pane_id> --timeout <ms>` as a background wait - a worker can land on
   any of those three terminal states and there's no single herdr status
   value that covers all of them, so this wrapper starts all three
   `herdr wait agent-status --status idle/blocked/done` waits internally,
   prints whichever one resolves first, and kills the other two, instead
   of you having to remember to launch all three yourself (a step that's
   been missed before, most recently `done`, leaving a stray wait running
   pointlessly). Run it in the background so I get notified the moment it
   resolves, instead of polling, and so it doesn't block your ability to
   keep talking to me in the meantime.
   **With more than one worker in flight:** launch one `herdr-wait-any`
   background wait per pane, for every worker not already
   idle/blocked/done, in the same turn - independent background Bash
   calls, not one after another. Starting worker B's wait only after
   worker A's resolves serializes your attention onto whichever worker
   happened to go first and can delay or miss the other one's
   completion entirely, which is exactly the "only hear from one worker
   at a time" failure this step exists to prevent.
3. Each background wait resolves independently and is reported back to
   you as its own notification - handle each one as it arrives on its
   own terms, don't wait for a second in-flight worker to also resolve
   before acting on the first. The moment one resolves (or if it was
   already idle/blocked/done): read that worker's actual last message
   (`herdr agent read <pane_id> --lines 40`) before doing anything else.
   `idle` just means the worker's turn ended - that can mean "task
   finished" or "it asked a question and is waiting," and those look
   identical from status alone. `blocked` means it's stuck on something
   it couldn't resolve itself. After handling it, resume waiting on
   whichever other workers are still in flight.

**If my own context gets cleared while workers are in flight**
4. Read `.claude/delegation/index.md` first to rebuild the roster, then
   read each listed worker's `<branch>.md` for its plan and last note.
   Treat both as a cache, not ground truth: immediately follow with
   `herdr agent list` and reconcile each worker's real pane status
   against what the files say before doing anything else - a worker may
   have finished, gotten stuck, or moved past its last written note
   since that file was updated. Resume the Wait/Review loop (steps 2-3)
   for each worker from its reconciled state, not its file state.

**Surface for Review or Relay a Question**
5. If the worker is actually done: it will have already opened its own
   `hunk diff` review pane (a sibling split in its tab, per the `delegate`
   skill's launch template) - don't try to run `hunk diff` yourself into
   the worker's own pane, that pane is still running its interactive
   claude session and would just receive it as a chat message, not a
   shell command. Confirm the diff pane exists (`herdr pane list
   --workspace <id>` or `herdr tab get <tab_id>`), then tell me
   explicitly which tab has it ready - don't wait to be asked.
6. If the worker asked a question, proposed a plan, or is blocked:
   relay it to me verbatim - don't guess an answer or approve a plan
   on its behalf, and don't treat it as done just because the pane is
   idle. Once I answer, send it into the worker's pane with
   `herdr-send-verified <pane_id> "<answer>"` and return to step 2.

**Relay Feedback**
7. Wait for my verdict on the diff.
8. If fixing is needed: `herdr-send-verified <pane_id> "<feedback>"` -
   the same verified settle/submit/retry call the `delegate` skill uses
   for the initial launch, now doing the same job for a follow-up
   message. Then return to step 2.
9. If good: ask what should happen next if I haven't already said
   (merge to a target branch, open a draft PR, rebase only, or
   something else) - never assume a default. Relay that instruction
   into the worker's pane the same way as feedback (`herdr-send-verified
   <pane_id> "<instruction>"`) - it already has the worktree, branch, and
   full context, so it does this itself, not you. For a merge, tell it
   to use `wt merge` (never raw git) - it squashes, rebases, runs
   pre-merge hooks as validation, fast-forwards into the target branch,
   and removes its own worktree and branch automatically as part of the
   same command. Then return to step 2 and wait for it like any other
   delegated step - it may hit its own blockers (merge conflicts,
   failing pre-merge hooks) that need relaying back to me.

**Clean Up**
10. Once the follow-up work is confirmed done and I've approved it: run
    `delegation-cleanup <branch>` - it closes the herdr tab and, unless
    the worker already ran `wt merge` (or anything else that self-removes
    the worktree), removes the worktree too, auto-detecting both the
    tab id and whether the worktree is already gone from the worker's own
    `.claude/delegation/<branch>.md` header (override with `--tab` or
    `--worktree-gone` if that file is missing or stale). My approval of
    the follow-up work is also approval to clean up - no separate
    check-in needed for this step.
11. Update `.claude/delegation/index.md`: set that worker's status to
    `done` (or `abandoned` if the work was dropped) and leave its line
    in place rather than deleting it - the worktree is gone, so the
    index line and its `<branch>.md` plan file are now the only record
    that the work happened. Then run `delegation-index-trim` - a no-op
    below ~20 entries, and past that it trims to the most recent ~20 as
    a matched deletion (not an archive): dropping the oldest roster
    line(s) also deletes their corresponding `<branch>.md` file(s) in
    the same step, so `index.md` never points at a plan file that no
    longer exists and no plan file outlives its roster line.

**Guardrails**
- Never skip the review step (5-6), even if the worker reports success.
- Never merge, push, or open a PR without my explicit confirmation in
  this session.
- Only run herdr control commands when `HERDR_ENV=1` is actually set -
  refuse and say so otherwise.
- Before clearing your own context with workers in flight, first make
  sure `.claude/delegation/index.md` and every active `<branch>.md` are
  current - write any pending updates yourself if a worker hasn't, then
  clear. Prefer this write-then-clear over letting auto-compaction run:
  the files are an inspectable, durable checkpoint that survives even
  if this terminal session is closed entirely, where a compacted
  summary only survives as long as this one session does.
