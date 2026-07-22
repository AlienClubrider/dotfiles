# Mechanizing the herdr/wt delegation workflow: scripts and skills proposal

Status: proposed, not implemented. No changes to `AGENTS.md` or `home.nix`
have been made. This document is for review; nothing here should be built
until it's approved.

## 1. Problem

`AGENTS.md`'s `## Delegation Workflow` section is ~15 numbered steps of prose
that Claude re-derives, live, every time it orchestrates a worker. Some of
that prose describes genuine judgment calls (does this task warrant
delegation, is a worker "done" or "asking a question"). But a large fraction
of it describes a fixed sequence of CLI calls with one correct shape and no
decision to make - and the section's own accumulated gotcha notes (the
workspace-omission failure mode, the send-text/pane-run paste race, the
`herdr-wait-any` three-way-wait requirement) are evidence that re-deriving
these mechanics from prose, under token pressure, produces real live
failures. `herdr-wait-any` (`home.nix:121`) already proves the pattern:
mechanize the part that has one right answer, keep prose for the part that
doesn't.

This proposes doing the same for the rest of the workflow's deterministic
steps, using `~/dev/brigade` and `~/.bosun/firstmate-home` as prior art -
both are heavier orchestrator/worker systems built around wezterm/tmux/herdr
panes that solved several of these exact problems already.

## 2. Prior art: what brigade and firstmate actually are

Both are three-tier systems (chef/captain -> brigade/firstmate ->
line-cook/crewmate workers) with a watcher daemon, durable wake queue, and
away-mode supervision - all disproportionate to our two-tier, no-daemon
setup. **firstmate is brigade's own upstream, materially ahead of it**:
brigade only has a wezterm adapter (`brigade-wezterm-lib.sh`,
`brigade-send.sh`); firstmate added a full runtime-backend abstraction
(`bin/fm-backend.sh` + `bin/backends/{tmux,herdr}.sh`) with herdr as a
verified, documented backend (`docs/herdr-backend.md`, 32KB of empirical
findings against real herdr 0.7.1). Since we use herdr directly, **firstmate's
`bin/backends/herdr.sh` is the directly relevant reference**, not brigade's.
Brigade is useful only where its wezterm-era logic and firstmate's herdr-era
logic still agree (e.g. the overall "verified-submit" shape).

Neither system's code is drop-in reusable - both are `fm-*`/`brigade-*`
prefixed, tied to their own `state/<id>.meta` layout and a `no-mistakes`
review-gate integration we don't have. What's reusable is the **algorithm**
in specific functions, and the **empirical facts** in `docs/herdr-backend.md`
that apply to any herdr caller, including ours.

### 2.1 Directly reusable: the verified send/submit algorithm

`bin/backends/herdr.sh`'s `fm_backend_herdr_send_text_submit` (line 351) is
firstmate's answer to exactly our step 5 paste-race problem. Ours currently
handles it as a fixed `sleep 2` guess plus a manual read-and-maybe-retry that
the orchestrator has to remember to do right. Theirs:

1. Send the text literal and unsubmitted (`pane send-text`).
2. Capture the pane as a "typed" baseline.
3. Loop: send `Enter` via `pane send-keys`, sleep, capture again. If the
   capture **changed** from the typed baseline, the send landed - done. If
   not, it's a swallowed Enter - retry (Enter only, never retype).
4. After `retries` attempts with no change, report `pending` (swallowed) so
   the caller can surface a real error instead of silently leaving unsent
   text sitting in the composer.

This is strictly better than our fixed-sleep-then-single-verify approach: it
retries automatically, it's delta-based (doesn't require guessing how long
"settled" takes), and it distinguishes a confirmed swallow from an
unreadable pane (`unknown`) from a hard CLI failure (`send-failed`) - three
outcomes our prose doesn't currently distinguish at all (our step 5(d) just
says "if it didn't [go through], ctrl+c and retry").

It also documents (and works around) a real herdr bug we'd otherwise hit
blind: `herdr pane read --lines N` returns **completely empty output**, not
a clamped result, when `N` is smaller than the pane's current viewport height
(~23 rows for a default pane) - `fm_backend_herdr_capture` (line 325) always
requests >=200 lines and trims locally with `tail -n N`. Any script we write
that does small bounded `herdr pane read` calls (composer verification, a
short status peek) needs this same workaround or it will flake exactly the
way their early smoke tests did.

### 2.2 Directly reusable: workspace/tab creation with duplicate-label guard

`fm_backend_herdr_workspace_ensure` + `fm_backend_herdr_create_task` (herdr.sh
lines 176-236) is the tab-creation half of our step 2. Notable pieces worth
porting:
- **Find-before-create for the workspace**, not assume-it-exists: resolves
  the workspace by label, creates only if absent. Our step 2 assumes
  `$HERDR_WORKSPACE_ID` is already set; a script that instead resolves-or-
  creates by a stable label removes that assumption as a failure mode
  entirely.
- **Duplicate tab-label check before creating**: herdr enforces no label
  uniqueness itself (verified in `docs/herdr-backend.md` "Label collisions"),
  so a caller that doesn't check can silently end up with two tabs sharing a
  branch name. Ours has no such check today.
- **`--no-focus` unconditionally** on both workspace and tab create, so
  spawning a worker never steals the human's attention away from whatever
  space they're looking at - verified empirically that this is a no-op in
  the already-safe case and real protection otherwise.
- **Robust `jq` parsing** of `tab_id`/`pane_id` out of the JSON result with an
  explicit "did both come back non-empty" check, rather than assuming the
  shape.

### 2.3 Relevant but not portable as code

- `fm-crew-state.sh`'s one-canonical-line-per-check design (`state: X ·
  source: Y · detail`) is a good *format convention* - reconciling a
  possibly-stale append-only log against an authoritative live source, and
  emitting one parseable, low-token line - but its actual logic is fused to
  firstmate's `no-mistakes` run-status integration, which we don't have. Our
  equivalent "authoritative source" is just `herdr agent get`'s
  `agent_status` directly (already what `herdr-wait-any` polls), so we don't
  need this reconciliation layer. Worth remembering as a pattern if we ever
  add our own append-only worker log.
- `fm-teardown.sh`'s "has this worktree's work actually landed" check is
  built around GitHub PR/merge detection via `gh-axi` and is considerably
  more defensive than we need, since `wt merge` already refuses unsafely.
  Not reusable, and not needed - `wt merge`'s existing guarantees cover this.
- `docs/herdr-backend.md`'s "`--session <name>`, not `HERDR_SESSION` alone"
  finding (a 2026-07-02 cleanup incident: the env var is silently ignored by
  some CLI subcommands once another herdr server is already running, but the
  explicit `--session` flag always routes correctly) doesn't apply to us
  today - we don't juggle multiple named herdr sessions - but is worth
  keeping in mind if that ever changes; the workaround is cheap (append
  `--session <name>` to every call) and firstmate applies it unconditionally
  for exactly this reason.

## 3. Mechanization candidates, ranked

Ranked by how often the step is called out as a repeat failure in
`AGENTS.md`'s own gotcha notes, and how purely mechanical (zero judgment) it
is.

### 3.1 `herdr-send-verified` (script) - highest priority

**Problem it replaces:** step 5's send-text/sleep-2s/send-keys-enter/verify/
retry dance (and step 12's identical dance for feedback), which today is
five separate tool calls the orchestrator must remember to sequence
correctly, with a fixed sleep instead of a real retry loop, and no
distinction between "confirmed swallowed" and "couldn't tell."

**Interface:**
```
herdr-send-verified <pane_id> <text...>
herdr-send-verified <pane_id> --key <Enter|Escape|ctrl+c>
```
Exit 0 on confirmed submit; exit 1 with a clear stderr message on a
confirmed swallow (text still sitting in the composer) or a hard send
failure; retries/settle tunable via `HERDR_SEND_RETRIES` /
`HERDR_SEND_SLEEP` env vars (mirroring `FM_SEND_RETRIES`/`FM_SEND_SLEEP`).

**Why a script, not a skill:** zero judgment anywhere in this operation -
same algorithm every single time, and it's pure shell/jq calling `herdr`,
exactly `herdr-wait-any`'s shape. Implement as
`pkgs.writeShellScriptBin "herdr-send-verified"` in `home.nix`, adapting the
delta-based retry loop from `fm_backend_herdr_send_text_submit`
(`~/.bosun/firstmate-home/bin/backends/herdr.sh:351`) and the `--lines`-bug
workaround from `fm_backend_herdr_capture` (same file, line 325).

**Effect on `AGENTS.md`:** collapses step 5's four-step lettered
send/wait/verify/retry sub-procedure (and step 12's "same way") down to one
command call plus a check of its exit code. The remaining prose only needs
to say *when* to call it (before spawning, when relaying feedback), not *how*
the send-and-verify mechanics work.

### 3.2 `herdr-spawn-tab` (script) - high priority

**Problem it replaces:** step 2's `herdr tab create --workspace ... --cwd ...
--label ...` plus manually noting `root_pane` from the JSON result, with the
known failure mode of a caller omitting `--workspace` and landing the tab in
whatever workspace currently has UI focus (possibly someone else's).

**Interface:**
```
herdr-spawn-tab <label> <cwd>
```
Resolves (find-or-create, never assumes) this orchestrator's own workspace
by a fixed label convention, checks for an existing tab with the same
`<label>` and refuses instead of silently duplicating, creates the tab with
`--no-focus`, and prints `<tab_id> <pane_id>` on one line for the caller to
capture. Exit 1 with a clear message on any resolution failure (missing
`herdr`/`jq`, workspace creation failure, duplicate label, unparseable
result).

**Why a script:** same reasoning as 3.1 - no judgment, deterministic CLI
sequence, direct port of `fm_backend_herdr_workspace_ensure` +
`fm_backend_herdr_create_task` (`backends/herdr.sh:176-236`). The one
decision this repo's version needs that firstmate's doesn't: what workspace
label to standardize on (we only ever have one orchestrator-per-project, not
firstmate's primary/secondmate-per-home split) - propose a fixed label like
`delegation` or derived from the repo name, resolved once and reused,
removing `$HERDR_WORKSPACE_ID` as an ambient variable the orchestrator has
to already have set correctly.

**Effect on `AGENTS.md`:** step 2 becomes "run `herdr-spawn-tab <branch>
<worktree_path>`, capture its `tab_id pane_id` output" - the workspace-
targeting footgun is eliminated structurally rather than by remembering to
pass a flag.

### 3.3 `delegate` (Claude Code skill) - high priority, different kind of win

**Problem it replaces:** the ~1000+ character worker-launch template in step
5 that the orchestrator must reproduce verbatim from prose memory on every
delegation, including the two-step `pane send-text` -> sleep -> `pane
send-keys enter` -> verify choreography around it (step 5's lettered a-d).
This is the single largest per-delegation token cost in the whole section,
and a verbatim-reproduction task is exactly where an LLM is likely to drop or
reword a clause under context pressure.

**Interface:** a `.claude/skills/delegate/SKILL.md` invoked as
`/delegate <branch>` (or similar), taking the already-approved plan content
as its argument/context. It would:
1. Call `wt switch --create <branch>`.
2. Call `herdr-spawn-tab <branch> <worktree_path>` (3.2) and capture ids.
3. Write `.claude/delegation/<branch>.md` with the fixed header/Goal/Plan/
   Notes shape (still filling in Goal/Plan prose from the conversation -
   that part isn't mechanizable, only the shape and boilerplate wrapper are).
4. Append the `index.md` line.
5. Compose the fixed worker-launch template (kept as a file the skill reads
   verbatim, parameterized only by branch/pane/path/task text) and send it
   via the two-call `herdr pane send-text` + `herdr-send-verified --key
   Enter` sequence (or better: once 3.1 exists, a single
   `herdr-send-verified <pane_id> "<full template>"` call, since 3.1 already
   *is* the settle-then-verify dance step 5 currently spells out by hand).

**Why a skill, not a pure script:** steps 3-4 need real content (the Goal
paragraph, the Plan checklist) that only the orchestrating LLM can produce
from the conversation - a skill can hold the fixed template/shape and drive
the deterministic script calls, while still leaving room for the model to
fill in the parts that need understanding. A pure shell script can't
generate the Goal/Plan text; a skill is the right level for "mostly
mechanical, with an LLM-authored payload in the middle."

**Effect on `AGENTS.md`:** step 5's entire lettered sub-procedure and the
giant inline template collapse to "invoke the `delegate` skill with the
approved plan" - the template itself moves out of prose (where it must be
retyped from memory) into a file (where it's read verbatim, every time,
correctly).

### 3.4 `delegation-index-trim` (script) - medium priority

**Problem it replaces:** step 15's "once `index.md` passes roughly 20 done
entries, trim to the most recent ~20, and delete the matching `<branch>.md`
files for whatever gets dropped" - a purely mechanical file-maintenance
operation currently described as an algorithm in prose that the orchestrator
has to execute correctly with ad hoc file edits (parse the table, count
rows, identify which to drop, delete the right files, rewrite the index).
Getting this wrong (dropping a row without deleting its file, or vice versa)
silently produces exactly the dangling-reference bug the step exists to
prevent.

**Interface:**
```
delegation-index-trim [--keep N]   # default N=20
```
Run from the orchestrator's own checkout root. Parses
`.claude/delegation/index.md`, and if it has more than `N` entries, drops the
oldest down to `N`, deleting each dropped entry's `<branch>.md` in the same
step. Idempotent - a no-op under the threshold.

**Why a script:** zero judgment (the threshold and the "matched deletion"
rule are already fully specified), and getting the row-count/file-deletion
pairing right by hand via `Edit` calls is exactly the kind of mechanical
bookkeeping a bug hides in easily. No direct brigade/firstmate equivalent
(their tracker is `tickets.toml`/`no-mistakes`-backed, not the markdown table
this repo chose in the prior status-tracking design), so this one is novel,
not ported.

**Effect on `AGENTS.md`:** step 15 becomes "run `delegation-index-trim`" -
the counting/dropping/matched-deletion algorithm moves out of prose
entirely, since prose was never the right place to encode "always keep these
two files in sync."

### 3.5 `delegation-cleanup` (script) - medium priority

**Problem it replaces:** step 14's conditional cleanup (if the worker already
`wt merge`d, the worktree's gone, just close the tab; otherwise `wt remove`
first, then close the tab).

**Interface:**
```
delegation-cleanup <branch> --tab <tab_id> [--worktree-gone]
```
Closes the herdr tab always; runs `wt remove <branch>` first unless
`--worktree-gone` is passed (or unless it detects the worktree path from
`.claude/delegation/<branch>.md` no longer exists on disk, making the flag
possibly unnecessary - worth deciding at implementation time whether to
require the flag explicitly or auto-detect).

**Why a script:** the *sequence* is deterministic once the "did it already
merge" fact is known; only that one upstream fact (relayed from the human's
approval) is a judgment call, and it's already resolved before this step
runs. Lower priority than 3.1/3.2 because it's not called out in
`AGENTS.md`'s own gotcha notes as something that has actually broken -
tidiness win, not a reliability fix.

### 3.6 Considered and rejected: mechanizing step 1 (`wt switch --create`)

Already a single, correct CLI call to an existing tool (`wt`) with no herdr
involvement and no known failure mode. Wrapping it would add a layer for no
benefit - the "use a real tool instead of raw git" mechanization already
happened when `wt` itself was adopted.

### 3.7 Considered and rejected: mechanizing step 9's review-pane check

Step 9 asks the orchestrator to confirm the worker's `hunk diff` pane exists
via `herdr pane list` / `herdr tab get`. This is mechanical and could be a
one-line script, but it isn't called out anywhere as a step that has broken
in practice, and reading its result still requires the same "is it actually
there" judgment either way - the win is marginal (saves recalling one CLI
invocation, not a multi-step dance) compared to 3.1-3.4. Worth a small script
only if it turns out to actually cause friction in practice; not worth
building preemptively.

## 4. What stays prose, and why

- **The `Delegation check:` decision itself** (trivial-direct vs.
  proposing-delegation) - a threshold judgment about the task at hand, not a
  fixed computation.
- **Re-stating the check when scope grows** - requires noticing that the
  task changed, which is exactly the kind of thing only the model doing the
  work can catch mid-stream.
- **Writing a worker's Goal/Plan content** - the shape can be templated (see
  3.3) but the content requires understanding the task; no script can write
  it.
- **Distinguishing "worker is done" from "worker asked a question" from a
  status of `idle`** (steps 7/9/10) - `herdr agent get` only reports a
  mechanical state (idle/blocked/done/working); interpreting what a worker's
  *last message* actually means is unavoidably a reading-comprehension task.
  This mirrors firstmate's own experience: `fm-crew-state.sh` exists
  specifically because their append-only status log goes stale and needs
  reconciliation against something authoritative, but even *their*
  authoritative source (a `no-mistakes` run's structured status) only
  resolves the "what phase is this in" question mechanically - it still
  can't tell "finished" from "asked a question and stopped," which is why
  their own workflow keeps a human/captain in that loop too, same as ours.
- **What to do after review** (step 13: merge target, draft PR, rebase only,
  something else) - explicitly "never assume a default," a decision that
  belongs to the human every time.
- **The guardrails section as a whole** - these are policies about when to
  ask versus act, not procedures with one right invocation.

## 5. Summary table

| Step(s) | Candidate | Type | Priority |
|---|---|---|---|
| 5 send dance, 12 feedback send | `herdr-send-verified` | script (`home.nix`) | highest - known repeat failure, direct port of a verified algorithm |
| 2 tab/workspace create | `herdr-spawn-tab` | script (`home.nix`) | high - known repeat failure (wrong workspace) |
| 3-5 worker launch (template + write files + send) | `delegate` skill | Claude Code skill | high - biggest token/fidelity win, needs LLM-authored payload |
| 15 index trim | `delegation-index-trim` | script (`home.nix`) | medium - pure bookkeeping, easy to get subtly wrong by hand |
| 14 cleanup | `delegation-cleanup` | script (`home.nix`) | medium - tidiness, not a known failure |
| 9 review-pane check | (none yet) | - | rejected for now - marginal, not a known failure |
| 1 worktree create | (none - `wt` already covers it) | - | rejected - already mechanized upstream |

## 6. Suggested implementation order, if approved

1. `herdr-send-verified` first - it's standalone, has the clearest prior-art
   port, and both the `delegate` skill (3.3) and step 12's feedback relay
   depend on it.
2. `herdr-spawn-tab` next - also standalone, removes the workspace footgun
   immediately even before the skill exists.
3. `delegate` skill, built on top of both scripts above.
4. `delegation-index-trim` and `delegation-cleanup` - independent of the
   above, can happen in either order or in parallel.

Each is a small, independently reviewable change; propose delegating them as
separate follow-up tasks rather than one large one, consistent with the
existing "does it touch more than one file" delegation threshold.
