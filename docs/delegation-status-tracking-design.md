# Markdown-based status tracking for the orchestrator/worker delegation workflow

Status: proposed design, not yet applied. No code or `AGENTS.md` changes have
been made; this document and the diff in section 5 are for review.

## 1. Problem

Today the only shared state between an orchestrator session and the workers
it spawns is the one-shot task string passed at `herdr pane run` time, plus
whatever the orchestrator remembers from `herdr agent read` transcripts. That
memory lives in the orchestrator's own context window. If the human clears
that window to avoid a slow/costly compaction while workers are still
running, the orchestrator loses track of which workers exist, what each is
doing, and what state they were in - there is nothing durable to reload from.

This document proposes writing that state to markdown files instead, so it
survives a context clear (or a closed terminal, or a crashed session)
independent of any one conversation's memory.

## 2. Prior art

### 2.1 Brigade (`/home/johanna/dev/brigade/AGENTS.md`)

Brigade is a much heavier three-tier system (head chef -> brigade -> line
cook/scout/sous-chef) with a watcher daemon, a durable wake queue, an
away-mode daemon, and a `tickets.toml`-backed task tracker. Most of that is
disproportionate to a two-tier orchestrator/worker setup with no daemon and
no polling loop. But several of its underlying design decisions are directly
reusable, independent of that machinery:

**Reusable:**

- **State lives outside the worktree that gets torn down.** Brigade's
  `data/<id>/brief.md` and `state/<id>.status` live under the brigade home
  (`FM_HOME`), never inside `projects/<repo>` (AGENTS.md:78-84). The worktree
  is disposable; the record of what happened in it is not. This is the load-
  bearing reason our plan/status files can't live inside the worker's own
  worktree - `wt merge`/`wt remove` would delete them along with everything
  else.
- **A thin, append-only status protocol, not verbose progress logging.**
  Line cooks append one line - `"<state>: <note>"` - only for
  "supervisor-actionable phase changes," explicitly because "every append
  wakes brigade" (AGENTS.md:82, 593). We have no wake mechanism to protect,
  but the same discipline avoids a worker turning its plan file into a
  running commentary that's expensive to re-read after a clear.
- **A thin central index, not a knowledge dump.** `data/backlog.md`
  (AGENTS.md:536-577) and `data/projects.md` (AGENTS.md:176-186) are
  deliberately kept to one line per item; "do not turn the registry into a
  knowledge dump," durable descriptive detail belongs in the per-item file,
  not the index. This maps directly onto separating our `index.md` (roster)
  from `<branch>.md` (the actual plan/status).
- **Status files are a cache, never the sole source of truth.** Section 8 is
  explicit and repeated: "Never rely on hooks or status files alone; the
  heartbeat review of every window is mandatory and unconditional... WezTerm
  is the ground truth" (AGENTS.md:461-462), and recovery (section 5) always
  cross-checks `state/*.meta`/`state/*.status` against actual live panes
  before trusting them (AGENTS.md:154-159). This is the single most
  important transferable principle: a markdown status file tells you what a
  worker *reported*, not what it's *doing right now*. Our design bakes this
  in as a mandatory reconciliation step against `herdr agent list`, not an
  optional sanity check.

  Note the translation, though: brigade talks to WezTerm directly, so
  WezTerm panes are literally its ground truth. Our workflow never talks to
  WezTerm directly - it always goes through herdr, which sits on top of
  WezTerm. The equivalent ground truth for us is whatever herdr reports
  (`herdr agent list`, `herdr pane list`, `herdr tab get`), not raw WezTerm
  state - herdr panes are WezTerm panes underneath, but we only ever
  observe or act on them through herdr. Section 3.3 already reflects this
  correctly; this note is just making explicit that the brigade quote above
  isn't to be read as "check WezTerm" for us.
- **A restart must be a non-event.** "All truth lives in WezTerm panes, state
  files, `data/backlog.md`... your conversation memory is a cache"
  (AGENTS.md:169-170). That's exactly the property the human is asking for:
  the orchestrator's own context window becomes a cache, not the record of
  truth.
- **Scout tickets end in a report file, not a PR** (AGENTS.md:293, 405-417) -
  the general pattern of "a delegated unit of work can produce a written
  artifact as its deliverable instead of only a code change" is the same
  shape as a worker's plan/status file: a first-class, durable, git-adjacent
  artifact, not a side effect of chat.

**Brigade-specific complexity to leave out:**

- The `tickets.toml`/`tasks-axi` backend and its verb set (`tasks-axi add
  --start --blocked-by`, `tasks-axi done --pr`, etc., AGENTS.md:556-576).
  That's dependency tracking and queue management across many concurrent
  tickets; our orchestrator delegates one thing at a time and reviews it
  before moving on.
- The watcher daemon, its exponential heartbeat backoff, the durable
  `.wake-queue`, and the guard-script liveness alarms (AGENTS.md:419-492).
  This whole apparatus exists because brigade supervises many unattended
  workers concurrently and needs to be paged. Herdr's `herdr wait
  agent-status --status idle/blocked --timeout` already gives us
  event-driven notification for the (normally one, occasionally a handful)
  workers we run; we don't need a background poller or a queue to make that
  durable.
- The away-mode (`/afk`) sub-supervisor daemon (AGENTS.md:494-507) - no
  equivalent need without unattended long-run operation being a stated goal.
- The three-role hierarchy and sous-chef "home" concept
  (AGENTS.md:18-21, 188-209, 396-403) - a persistent, domain-scoped second
  brigade instance. We have exactly one orchestrator and flat workers.
- Delivery-mode branching (`no-mistakes` / `direct-PR` / `local-only`) and
  the `yolo` approval-bypass flag (AGENTS.md:235-260, 352-363). Our workflow
  already has a single, simpler merge path (`wt merge`) and a flat human-
  approval gate; we don't need per-project pipeline configuration.
- The Recipe system (`~/.brigade/recipes/<repo>/AGENTS.md`,
  AGENTS.md:333-339) - a separate personal-preferences layer on top of
  project `AGENTS.md`. Out of scope for this problem.

### 2.2 External frameworks and practitioner writing

- **LangGraph checkpointing.** Persistence is layered: a *checkpointer*
  snapshots full graph state at every step, keyed by a `thread_id`, giving
  resume-after-failure and time-travel; a separate *store* holds long-term
  cross-thread memory. Production guidance is to move off the in-memory
  saver to a real backend (Postgres, DynamoDB, etc.) once you need
  durability beyond one process's lifetime. The transferable idea: separate
  the unit that must survive a crash (checkpoint/thread) from the unit that
  persists longer-term (store) - which maps onto our `<branch>.md` (per-
  worker, thread-scoped) vs. `index.md` (persists across many workers).
  ([Docs by LangChain: Persistence](https://docs.langchain.com/oss/python/langgraph/persistence))
- **Letta / MemGPT.** An OS-inspired three-tier memory model: core memory
  (small, always in-context, the agent edits it directly via tool calls),
  recall memory (recent history, searchable but out-of-context), archival
  memory (long-term, embedding-searched). Critically, when context fills,
  MemGPT does not discard - it summarizes evicted messages and *keeps the
  original* in recall storage, so nothing is silently lost even though it's
  no longer in-context. That's a stronger guarantee than either Claude Code's
  `/compact` (lossy, no separately-queryable original) or `/clear` (nothing
  kept at all unless you wrote it down yourself) - worth naming as the
  ceiling this design doesn't reach, since we're relying on the worker/
  orchestrator to *choose* to write the durable copy rather than having the
  harness guarantee it. ([Letta: Memory Blocks](https://www.letta.com/blog/memory-blocks/), [Agent Memory: How to Build Agents That Learn and Remember](https://www.letta.com/blog/agent-memory/))
- **CrewAI.** The `@persist` decorator checkpoints Flow state to a database
  so a crashed or interrupted run can resume; the community's own caveat is
  that this only checkpoints at *task boundaries* - the inner reasoning loop
  of a single running agent step is not persisted, so a crash mid-step still
  loses that step's progress and must restart it. This is a direct precedent
  for the worker-side recommendation below: checkpoint at clean step
  boundaries, not arbitrarily mid-action.
  ([CrewAI: Debugging State Persistence](https://community.crewai.com/t/debugging-state-persistence-when-does-persist-save-flow-state/5884), [Your AI Agent Crashed at Step 47. Now What?](https://dev.to/george_belsky/your-ai-agent-crashed-at-step-47-now-what-41mb))
- **AutoGPT-style agents.** Common practitioner pattern: append thoughts/
  tasks/results to a JSON or markdown file at a known path as the run
  progresses; on restart, reload from that same path. The recurring failure
  mode called out across sources is the opposite of our problem - letting
  memory accumulate without ever resetting causes context bloat from the
  agent's own accumulated mistakes and false assumptions, which is exactly
  why brigade's status lines and our plan file both stay terse and append-
  only rather than becoming a full transcript.
  ([Fastio: AI Agent Memory Persistence Guide](https://fast.io/resources/ai-agent-memory-persistence-guide/))
- **Anthropic's own compaction docs and guidance.** Server-side compaction
  (`context_management.edits`, beta) auto-summarizes when input tokens cross
  a trigger (default 150k) and is described as "the recommended strategy for
  managing context in long-running conversations and agentic workflows" at
  the API level - but it bills an extra sampling iteration for the summary
  itself, which is exactly the "slow/costly" cost the human is trying to
  avoid by clearing instead.
  ([Compaction - Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/compaction))
  The Claude Code-specific guidance is narrower and more relevant to us:
  `/compact` is "low effort," lets Claude decide what matters, and suits a
  session "bloated with stale debugging/exploration" mid-task; `/clear`
  costs you the work of writing down what's relevant yourself but gives
  "zero rot" and "you control exactly what carries forward," and is
  preferred when starting a genuinely new task or when context is poisoned
  by incorrect assumptions the model keeps reverting to.
  ([Using Claude Code: session management and 1M context](https://claude.com/blog/using-claude-code-session-management-and-1m-context))
- **"Context rot" and the STATE.md pattern.** Independent practitioner
  writing on long Claude Code sessions converges on the same fix: context
  degrades gradually (not just at the hard limit), and what degrades first
  is *stated intent* - a constraint mentioned once forty messages ago simply
  stops influencing behavior once it rots out of relevance, well before it's
  evicted outright. The documented mitigation is a `STATE.md` file with
  fixed sections (Objective, Constraints, Decisions, Current Status, Next
  Steps), updated as things change, with the practice of clearing the
  session and reloading only that file plus the relevant source once outputs
  start drifting - i.e., write-then-clear, not compact-and-hope, and not
  wait-for-degradation-to-become-obvious.
  ([Towards Data Science: Governed Context - Managing Context Rot in Claude Code](https://towardsdatascience.com/governed-context-managing-context-rot-in-claude-code/))

Our `<branch>.md` plan/status file is functionally this STATE.md pattern,
specialized to a delegated coding task: `## Goal` is Objective, the plan
checklist is Decisions/Next-Steps combined, and the Notes section is Current
Status.

## 3. Design

### 3.1 File layout

```
<orchestrator's own checkout>/.claude/delegation/
  index.md          # roster: one line per worker, active or recently done
  <branch>.md        # one plan/status file per worker, named after its branch
```

**Centralized, not per-worktree**, and rooted in the *orchestrator's own*
working directory (the long-lived checkout the human is actually typing
into), never inside a worker's disposable worktree. Two independent reasons
converge on this, both drawn from section 2:

1. A worker's worktree gets deleted by `wt merge`/`wt remove` on cleanup
   (brigade AGENTS.md:33-36 makes the equivalent rule explicit: never tear
   down a worktree holding unlanded work, and the corollary is that anything
   meant to outlive the worktree can't live inside it). If the plan/status
   file lived in the worktree, the audit trail of *what happened* would
   vanish at the exact moment the work lands - the opposite of durable.
2. It keeps the worker's `hunk diff` review pane clean. `hunk diff` shows
   uncommitted changes in the worker's own worktree; a plan file living
   there would show up as noise in every review alongside the actual code
   diff the human is trying to evaluate.

`.claude/delegation/` is added to `.git/info/exclude` in the orchestrator's
checkout - reusing the exact mechanism `agents-init` already uses for
`AGENTS.md`/`CLAUDE.md` (local-only, untracked, never staged or committed).
This assumes the orchestrator's own checkout is a stable, long-lived clone
(the human's primary working directory for that project) rather than itself
a short-lived worktree - true today, since delegation always spins up a
*separate* worktree for the worker rather than working in place.

Workers need read/write access to a path outside their own worktree (their
own `<branch>.md`). Worktrees are plain sibling directories on the same
filesystem (this very session's cwd,
`dotfiles.plan-markdown-status-tracking`, is a sibling of the primary
`dotfiles` checkout), so an absolute path works with no sandboxing to work
around. This is a real, if narrow, increase in what a worker touches outside
its assigned worktree, so the worker's instructions say explicitly: touch
only that one file outside your own worktree, nothing else. The worker never
touches `index.md` - only the orchestrator does, which avoids any risk of
two concurrently-running workers racing on a shared file.

**Naming:** `<branch>.md` reuses the same branch name already used for
`wt switch --create <branch>` and the herdr tab label, so there is exactly
one identifier per worker to keep straight instead of two.

### 3.2 Update protocol

**Orchestrator, before spawning (new steps 3-4 in the workflow):**
1. Write `.claude/delegation/<branch>.md` with a fixed shape: a one-line
   status/tab/pane/worktree header, a `## Goal` paragraph, a `## Plan`
   checklist (the approved plan, verbatim, if one was already discussed and
   approved - matching the existing "Plan (pre-approved)" carve-out so the
   worker doesn't re-derive or re-pause on something already agreed), and an
   empty `## Notes` section for the worker to append to.
2. Add one line to `index.md`: branch, tab/pane id, one-line goal, status,
   the plan file's path, last-updated date.

**Worker, during the task:** check off each `## Plan` step as it's completed,
and append a single dated line to `## Notes` only on a real phase change -
blocked, a question, or done - mirroring brigade's "only supervisor-
actionable phase changes" discipline, not a line per tool call. This keeps
the file cheap to write and cheap to re-read after a clear, rather than
turning into a second transcript.

**Orchestrator never writes to a worker's `<branch>.md` mid-task** - the file
is the worker's single-writer scratchpad while it's live, avoiding any
concurrent-write hazard. The orchestrator only touches a worker's file after
that worker is idle/blocked/done (updating `status:` in the header) and only
ever writes `index.md` itself.

**On teardown:** set that worker's `index.md` line to `status: done` (or
`abandoned`) rather than deleting it - the worktree is gone, so the index
line and the plan file are now the only record that the work happened.
Trim `index.md` to roughly its most recent 20 done entries once it grows
long (brigade does the equivalent for `data/backlog.md`'s Done section,
capped at 10, though brigade archives pruned entries to
`data/done-archive.md` rather than deleting them). Our trim is a matched
deletion, not an archive: dropping the oldest one-line roster entries from
`index.md` past ~20 done also deletes the corresponding `<branch>.md`
file(s) for those same entries, in the same step. This is a deliberate
choice to keep disk usage bounded and the index and the set of surviving
plan files always in sync - `index.md` never points at a `<branch>.md`
that no longer exists, and no `<branch>.md` outlives its roster line.

### 3.3 Reconstruction after a context clear

New step, inserted between "Wait" and "Surface for Review" in the workflow:

1. Read `index.md` to rebuild the roster of who's running.
2. Read each listed worker's `<branch>.md` for its plan and last note.
3. Immediately reconcile both against `herdr agent list` (and `herdr agent
   read` for anything that looks off) before acting on anything - per
   brigade's explicit rule (2.1), the files are a cache of what was last
   *reported*, not what's happening *right now*. A worker may have finished,
   gotten blocked, or moved three steps past its last written note since
   the file was updated.
4. Resume the normal Wait/Review loop per worker from its reconciled live
   state, not its file state.

This is the same shape as brigade's Recovery section (AGENTS.md:146-170):
drain/read persisted state first, then cross-check every live pane before
trusting it, and only escalate to the human what actually needs their
attention.

## 4. Clear vs. compact: concrete recommendation

### Orchestrator

**Write-then-clear, not compact, and not a passive wait for auto-compaction.**

Before clearing, update `index.md` and every active `<branch>.md` so they're
current (writing any update a worker hasn't gotten to itself, if needed),
then `/clear`. Reasoning:

- This matches the human's stated motivation directly - compaction here is
  the thing being avoided for cost/latency reasons, and Anthropic's own
  compaction docs confirm it isn't free: it bills a separate summarization
  iteration on top of the conversation (2.2). Fighting that stated
  constraint by recommending compaction anyway would ignore the actual
  problem.
- More importantly, independent of cost: a compacted summary is lossy text
  that lives only inside that one session and is only as good as the
  model's judgment of what mattered at compaction time. A written markdown
  file is a deterministic, inspectable, diffable checkpoint that survives
  even if the terminal is closed entirely, not just if the token budget
  resets - the same reason LangGraph pushes real state to a durable
  checkpointer instead of relying on the model to carry it, and the same
  reason the STATE.md pattern (2.2) explicitly pairs "write state" with
  "then clear," not "then compact."
- The orchestrator's context is dominated by herdr tool output and
  back-and-forth relay chat, which is exactly the "bloated with stale
  debugging/exploration" case Claude Code's own guidance says `/compact`
  suits - so compact would *work* here. The reason to still prefer clear is
  that the design already produces a better artifact than a compaction
  summary would (a structured, worker-scoped file instead of one
  undifferentiated prose blob), so paying compaction's cost buys nothing
  clear-plus-files doesn't already give for free.

### Worker

**Prefer write-then-clear at a clean plan-step boundary; fall back to
letting compaction run if caught mid-step with no clean boundary reachable
in time.** This is a genuine two-branch recommendation, not a single answer,
because a worker's situation differs from the orchestrator's in one
important way: a worker's context holds fine-grained working state (which
files were read, what was tried and reverted, why an approach was chosen)
that a short status note cannot cheaply capture in full, whereas the
orchestrator's context is mostly reconstructable from the plan/index files
plus herdr transcripts by design.

- **Common case - near a clean boundary (just finished a plan step, tests
  passing):** finish the step, check it off, write a short resume note
  under `## Notes` if anything not obvious from the checklist matters (a
  gotcha, a file to revisit, why an alternate approach was rejected), then
  clear and re-read the plan file to resume. This is directly the CrewAI
  `@persist` lesson (2.2): checkpoint at task boundaries, because the inner
  loop of an in-progress step is what doesn't survive a reset cleanly
  either way, so there's no real cost to clearing once that inner loop has
  already resolved into a completed, checked-off step.
- **Exception - caught mid-step, no clean boundary reachable soon:** let
  compaction run instead of forcing a clear. A rushed, incomplete status
  note written just to justify clearing captures less than an automatic
  summary would, and a bad clear at a dirty checkpoint (mid-edit, tests
  failing, half-migrated state) is worse than a compacted continuation -
  the summary at least carries forward the in-progress detail a hurried
  note would drop. This mirrors MemGPT's design choice (2.2) to summarize
  and retain rather than discard when forced to evict mid-flight, instead
  of forcing an artificial boundary that isn't really there.

The dividing line in practice: if the next tool call would leave the
worktree in a state you wouldn't want to hand to another engineer
unexplained, that's "no clean boundary" - let compaction run. If the next
tool call would just start the *next* checklist item, that's a clean
boundary - write the note and clear.

## 5. Proposed diff to `AGENTS.md`'s Delegation Workflow section

Not applied. Diffed against the current section of this repo's `AGENTS.md`
(both project and global copies currently carry the same text there).

```diff
--- AGENTS.md (current Delegation Workflow section)
+++ AGENTS.md (proposed Delegation Workflow section)
@@ -25,67 +25,129 @@
 a "quick fix" turns out to touch a second file) - don't keep working
 just because you already started.
 
+### Delegation state directory
+
+Keep a `.claude/delegation/` directory at the root of your own working
+checkout (never inside a worker's worktree - that gets torn down on
+merge). Add it to `.git/info/exclude` the same way `agents-init` already
+excludes `AGENTS.md`/`CLAUDE.md`, so it never gets staged or committed.
+It holds:
+- `index.md` - one line per active or recently-finished worker, the
+  roster you rebuild everything else from.
+- `<branch>.md` - one plan/status file per worker, named after its
+  branch.
+
+These files are a durable checkpoint, not a replacement for live status:
+always reconcile them against `herdr agent list` / `herdr agent read`
+before acting on them, especially right after a context clear - a file
+can lag what a worker's pane is actually doing.
+
 **Delegate** (only after I say yes)
 1. `wt switch --create <branch>` - always in its own worktree, never work
    on a delegated task directly. `agents-init`'s wiring runs automatically.
 2. `herdr tab create --cwd <worktree_path> --label <branch>` - one new
    tab per worker. Note the `root_pane` id from the result.
-3. If you and I already discussed and approved an approach before
-   delegating (per the Workflow section above), carry that plan into
-   `<task>` verbatim, labeled `Plan (pre-approved): ...` - don't make
-   the worker re-derive and re-pause on a plan we already agreed on.
-   `herdr pane run <pane_id> "claude --permission-mode auto 'You are a
+3. Write the plan to `.claude/delegation/<branch>.md` before spawning.
+   Use this shape:
+
+   ```markdown
+   # <branch>
+   status: in_progress
+   tab: <tab_id>  pane: <pane_id>  worktree: <worktree_path>
+   started: <date>
+
+   ## Goal
+   <one paragraph>
+
+   ## Plan
+   - [ ] <step>
+   - [ ] <step>
+
+   ## Notes
+   (worker appends dated one-line notes here: blocked/question/done)
+   ```
+
+   If you and I already discussed and approved an approach before
+   delegating (per the Workflow section above), write that approved plan
+   into the `## Plan` checklist verbatim - don't make the worker
+   re-derive and re-pause on a plan we already agreed on.
+4. Add a line for it to `.claude/delegation/index.md`:
+   `- <branch> - <tab_id>/<pane_id> - <one-line goal> - status: in_progress - plan: .claude/delegation/<branch>.md (updated <date>)`
+5. `herdr pane run <pane_id> "claude --permission-mode auto 'You are a
    delegated worker with no further delegation available - do not spin
-   up another worker or worktree. You have no direct channel to the
-   human: if the task includes a plan labeled Plan (pre-approved),
-   execute it directly with no further planning pause. Otherwise, if
-   the task is non-trivial, state your plan as your next message and
-   then stop without editing anything - your orchestrator will relay my
-   go-ahead or feedback back into this session before you proceed. When
-   you are fully done, before ending your turn, open a review pane
-   yourself: herdr agent start hunk-diff --tab "$HERDR_TAB_ID" --split
-   right --cwd <worktree_path> -- hunk diff (use your own working
-   directory; --tab pins it to your own tab instead of whatever tab
-   happens to have UI focus, and --split right is the vertical/
-   side-by-side split, not --split down which stacks panes
-   horizontally). Do not consider the task finished until that pane
-   exists. <task>'"` in that same pane - a complete, self-contained task
-   description; the worker starts cold, with no access to this
-   conversation. Auto mode keeps it from stalling on routine
-   tool-permission prompts.
+   up another worker or worktree. Read <absolute path to
+   .claude/delegation/<branch>.md> first - it holds your plan. If it has
+   a Plan section, execute it directly with no further planning pause.
+   Otherwise, if the task is non-trivial, state your plan as your next
+   message and then stop without editing anything - your orchestrator
+   will relay my go-ahead or feedback back into this session before you
+   proceed. As you complete each plan step, check it off in that same
+   file and, on any blocked/question/done state change, append a one-line
+   dated note under its Notes section - that file is the only line of
+   contact between your work and my orchestrator once I clear my own
+   session, so keep it current, but only on real phase changes, not
+   every tool call. That file lives outside your worktree; touch nothing
+   else there. If you get close to your own context limit mid-task,
+   prefer finishing the current plan step, writing its status/notes
+   update, and only then clearing your context to re-read the plan file
+   and resume - do not clear mid-step with nothing written down. If you
+   are cut off mid-step with no clean stopping point in reach, let
+   compaction run instead of clearing; a compacted summary still carries
+   the in-progress detail a rushed note would lose. When you are fully
+   done, before ending your turn, open a review pane yourself: herdr
+   agent start hunk-diff --tab "$HERDR_TAB_ID" --split right --cwd
+   <worktree_path> -- hunk diff (use your own working directory; --tab
+   pins it to your own tab instead of whatever tab happens to have UI
+   focus, and --split right is the vertical/side-by-side split, not
+   --split down which stacks panes horizontally). Do not consider the
+   task finished until that pane exists. <task>'"` in that same pane - a
+   complete, self-contained task description; the worker starts cold,
+   with no access to this conversation. Auto mode keeps it from stalling
+   on routine tool-permission prompts.
 
 **Wait**
-4. Check current status first (`herdr agent list`, find the pane). If
+6. Check current status first (`herdr agent list`, find the pane). If
    not already `idle` or `blocked`, run `herdr wait agent-status
    <pane_id> --status idle --timeout <ms>` as a background command so I
    get notified the moment it resolves, instead of polling - don't block
    your ability to keep talking to me in the meantime.
-5. The moment it resolves (or if it was already idle/blocked): read the
+7. The moment it resolves (or if it was already idle/blocked): read the
    worker's actual last message (`herdr agent read <pane_id> --lines
    40`) before doing anything else. `idle` just means the worker's turn
    ended - that can mean "task finished" or "it asked a question and is
    waiting," and those look identical from status alone. `blocked` means
    it's stuck on something it couldn't resolve itself.
 
+**If my own context gets cleared while workers are in flight**
+8. Read `.claude/delegation/index.md` first to rebuild the roster, then
+   read each listed worker's `<branch>.md` for its plan and last note.
+   Treat both as a cache, not ground truth: immediately follow with
+   `herdr agent list` and reconcile each worker's real pane status
+   against what the files say before doing anything else - a worker may
+   have finished, gotten stuck, or moved past its last written note
+   since that file was updated. Resume the Wait/Review loop below for
+   each worker from its reconciled state, not its file state.
+
 **Surface for Review or Relay a Question**
-6. If the worker is actually done: it will have already opened its own
-   `hunk diff` review pane (a sibling split in its tab, per step 3) -
+9. If the worker is actually done: it will have already opened its own
+   `hunk diff` review pane (a sibling split in its tab, per step 5) -
    don't try to run `hunk diff` yourself into the worker's own pane,
    that pane is still running its interactive claude session and would
    just receive it as a chat message, not a shell command. Confirm the
    diff pane exists (`herdr pane list --workspace <id>` or `herdr tab
    get <tab_id>`), then tell me explicitly which tab has it ready -
    don't wait to be asked.
-7. If the worker asked a question, proposed a plan, or is blocked: relay
-   it to me verbatim - don't guess an answer or approve a plan on its
-   behalf, and don't treat it as done just because the pane is idle.
-   Once I answer, send it into the worker's pane and return to step 4.
+10. If the worker asked a question, proposed a plan, or is blocked:
+    relay it to me verbatim - don't guess an answer or approve a plan on
+    its behalf, and don't treat it as done just because the pane is
+    idle. Once I answer, send it into the worker's pane and return to
+    step 6.
 
 **Relay Feedback**
-8. Wait for my verdict on the diff.
-9. If fixing is needed: `herdr pane run <pane_id> "<feedback>"` (typed as
-   a new message into the worker's session), then return to step 4.
-10. If good: ask what should happen next if I haven't already said
+11. Wait for my verdict on the diff.
+12. If fixing is needed: `herdr pane run <pane_id> "<feedback>"` (typed
+    as a new message into the worker's session), then return to step 6.
+13. If good: ask what should happen next if I haven't already said
     (merge to a target branch, open a draft PR, rebase only, or
     something else) - never assume a default. Relay that instruction
     into the worker's pane the same way as feedback - it already has the
@@ -93,12 +155,12 @@
     For a merge, tell it to use `wt merge` (never raw git) - it squashes,
     rebases, runs pre-merge hooks as validation, fast-forwards into the
     target branch, and removes its own worktree and branch automatically
-    as part of the same command. Then return to step 4 and wait for it
+    as part of the same command. Then return to step 6 and wait for it
     like any other delegated step - it may hit its own blockers (merge
     conflicts, failing pre-merge hooks) that need relaying back to me.
 
 **Clean Up**
-11. Once the follow-up work is confirmed done and I've approved it: if
+14. Once the follow-up work is confirmed done and I've approved it: if
     the worker already ran `wt merge` (or anything else that
     self-removes the worktree), the worktree and branch are already
     gone - just close the herdr tab (`herdr tab close <tab_id>`). If the
@@ -107,10 +169,26 @@
     (never raw `git worktree`), then close the tab. My approval of the
     follow-up work is also approval to clean up - no separate check-in
     needed for this step.
+15. Update `.claude/delegation/index.md`: set that worker's status to
+    `done` (or `abandoned` if the work was dropped) and leave its line in
+    place rather than deleting it, so the record of what ran survives
+    the teardown of its worktree. Leave the `<branch>.md` plan file where
+    it is too - it is now the durable record of that piece of work. Once
+    `index.md` passes ~20 done entries, trim it to the most recent ~20 -
+    this deletes both the oldest roster line(s) and their corresponding
+    `<branch>.md` file(s) together, so the index and the set of surviving
+    plan files stay in sync and disk usage stays bounded.
 
 **Guardrails**
-- Never skip the review step (6-7), even if the worker reports success.
+- Never skip the review step (9-10), even if the worker reports success.
 - Never merge, push, or open a PR without my explicit confirmation in
   this session.
 - Only run herdr control commands when `HERDR_ENV=1` is actually set -
   refuse and say so otherwise.
+- Before clearing your own context with workers in flight, first make
+  sure `.claude/delegation/index.md` and every active `<branch>.md` are
+  current - write any pending updates yourself if a worker hasn't, then
+  clear. Prefer this write-then-clear over letting auto-compaction run:
+  the files are an inspectable, durable checkpoint that survives even if
+  this terminal session is closed entirely, where a compacted summary
+  only survives as long as this one session does.
```

## 6. Open questions / risks for the human to weigh

- **Worker write-scope increase.** Workers currently touch only their own
  worktree. This design has them write one specific file one directory tree
  over, in the orchestrator's checkout. The instructions constrain it to
  exactly that one path, but it's a real (if narrow) departure from "worker
  never touches anything outside its worktree" that's worth deciding on
  explicitly rather than inheriting by default.
- **No enforcement, only convention.** Nothing stops a worker from ignoring
  the plan file or the orchestrator from forgetting to write `index.md`
  before clearing - same as every other rule in this workflow today.
  Brigade's `brigade-guard.sh` (2.1) exists precisely to catch this kind of
  drift mechanically; this design has no equivalent, on the theory that a
  daemon/guard-script layer is exactly the brigade-specific complexity
  section 2.1 argues against copying at our current scale. Worth revisiting
  if staleness turns out to be a recurring problem in practice.
- **`index.md` growth and the trim's data loss.** The soft 20-entry trim
  (3.2) is a guess, not a measured number - there's no data yet on how
  many workers typically run before the human circles back to prune it.
  Also worth flagging explicitly: the trim is a matched deletion, not an
  archive - past ~20 done entries, both the roster line in `index.md` and
  the corresponding `<branch>.md` file are deleted together, so the
  detailed plan/notes for anything older than the most recent ~20 done
  workers is genuinely gone, not just delisted. That's the intended
  tradeoff (bounded disk usage, index and files always in sync), but it's
  a one-way door once it fires, unlike brigade's archive-to-a-file
  approach for `data/backlog.md`.
