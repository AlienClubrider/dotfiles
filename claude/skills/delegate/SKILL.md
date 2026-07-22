---
name: delegate
description: Spawns one delegated worker for the herdr/wt orchestrator/worker delegation workflow - creates its worktree and herdr tab, writes its .claude/delegation/<branch>.md plan file and index.md roster line, and sends its worker-launch instructions. Use only after the human has already approved delegating a specific task (per AGENTS.md's Delegation Workflow) and you already have its Goal and Plan content ready to write.
---

# delegate

Mechanizes the fixed, no-judgment mechanics of spawning one delegated worker
in the herdr/wt Delegation Workflow (`AGENTS.md`'s `## Delegation Workflow`
section): worktree creation, herdr tab creation, the plan/index file shape,
and the verified send of the worker-launch instructions. What it does NOT
do: decide whether to delegate, or write the Goal/Plan content - both of
those are your job, already done by the time you invoke this skill.

**Precondition:** the human has already said yes to delegating this specific
task (the `Delegation check:` / approval step in `AGENTS.md` already
happened), and you already have the Goal paragraph and Plan checklist ready
- verbatim, if you and the human already settled on an approach together.
`HERDR_ENV` must be `1` (refuse and say so otherwise, per `AGENTS.md`'s own
guardrail).

Argument: `<branch>` - the branch name to delegate under (used for the
worktree, the herdr tab label, and `.claude/delegation/<branch>.md`).

## Steps

1. **Create the worktree.**
   ```bash
   wt switch --create <branch>
   ```
   Note its absolute worktree path (`wt switch` prints it, or resolve it with
   `wt list --format=json | jq -r '.[] | select(.is_current) | .path'` from
   inside it).

2. **Create the herdr tab.**
   ```bash
   herdr-spawn-tab <branch> <worktree_path>
   ```
   Prints `<tab_id> <pane_id>` on success, or a clear error on stderr (a
   duplicate tab label, a missing `herdr`/`jq`, an unparseable result) - if it
   errors, stop and report the error rather than improvising a workaround.

3. **Ensure the delegation state directory exists and is git-excluded**, from
   your own checkout root (not the worker's worktree):
   ```bash
   mkdir -p .claude/delegation
   grep -qxF '.claude/delegation' .git/info/exclude 2>/dev/null || echo '.claude/delegation' >> .git/info/exclude
   ```

4. **Write `.claude/delegation/<branch>.md`** with this fixed shape - fill in
   the header fields from steps 1-2 and today's date, and the Goal/Plan
   content you already have:
   ```markdown
   status: in_progress
   tab: <tab_id>
   pane: <pane_id>
   worktree: <worktree_path>
   branch: <branch>
   started: <date>

   ## Goal

   <the goal paragraph>

   ## Plan

   - [ ] <step>
   - [ ] <step>

   ## Notes
   ```

5. **Append one line to `.claude/delegation/index.md`**, in this exact
   pipe-delimited shape (matches the existing convention - keep it a single
   line):
   ```
   - <branch> | tab <tab_id> | pane <pane_id> | goal: <one-line goal> | status: in_progress | plan: .claude/delegation/<branch>.md | <date>
   ```

6. **Compose the worker-launch instructions** from `worker-launch-template.txt`
   (in this skill's own directory) by substituting:
   - `{{PLAN_FILE}}` - absolute path to `.claude/delegation/<branch>.md`
   - `{{TAB_ID}}` - the tab id from step 2
   - `{{WORKTREE_PATH}}` - the worktree path from step 1
   - `{{TASK}}` - a short task description. **Never fold a commit instruction
     in here** - the worker's own review pane opens with `hunk diff`, which
     shows only uncommitted working-tree changes, so committing before
     review leaves it empty; committing and merging happen later, after the
     human's verdict, as separate relayed instructions.

   Read the template file verbatim and only substitute the four placeholders
   above - do not paraphrase or reconstruct it from memory.

7. **Escape embedded single quotes** in the composed text before wrapping it
   in the outer `claude --permission-mode auto '...'` invocation, since the
   text is about to be typed into the *worker's own* shell, which will parse
   an unescaped `'` as closing the argument early (a contraction like
   "task's" or "worker's" anywhere in the Goal/Plan/task text you substituted
   in would otherwise truncate the command). Replace every `'` with `'\''`
   in the substituted text, THEN wrap the whole thing in single quotes:
   ```bash
   rendered_escaped=$(printf '%s' "$rendered" | sed "s/'/'\\\\''/g")
   final_command="claude --permission-mode auto --prompt-suggestions false '$rendered_escaped'"
   ```

8. **Send it, verified, in one call** - `herdr-send-verified` already is the
   settle-then-verify-then-retry dance that used to be a manual multi-step
   procedure:
   ```bash
   herdr-send-verified <pane_id> "$final_command"
   ```
   A non-zero exit means the send is NOT confirmed to have landed (a
   swallowed Enter, an unreadable pane, or a hard send failure) - stop and
   report this rather than assuming it went through.

9. Two flags are already baked into the launch template, not something to
   add separately: auto mode (`--permission-mode auto`) keeps the worker
   from stalling on routine tool-permission prompts, and
   `--prompt-suggestions false` keeps the worker's pane from ever showing
   a predicted-next-prompt that could be mistaken for real typed input.

## After this skill returns

You still own the judgment calls this skill doesn't make: waiting for the
worker (`herdr-wait-any`), reading its actual last message to tell "done"
from "asked a question," relaying feedback, and deciding what happens after
review. See `AGENTS.md`'s `## Delegation Workflow` section for those steps.
