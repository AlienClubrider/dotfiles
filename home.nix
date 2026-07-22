{ pkgs, lib, config, isLinux, ... }:

let
  username = builtins.getEnv "USER";

  aliases = {
    ll = "eza -la";
    ls = "eza";
    cat = "bat";
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gp = "git push";
    gl = "git log --oneline --graph --decorate";
    vim = "nvim";
    vi = "nvim";
    t = "tmux";
    ta = "tmux attach";
    tn = "tmux new -s";
    tl = "tmux ls";
    tk = "tmux kill-session -t";
  };

  # Generated from `aliases` above so it can never drift out of sync with
  # what's actually configured. Named "myshortcuts" (not "shortcuts") to
  # avoid colliding with macOS's built-in /usr/bin/shortcuts CLI.
  myshortcuts = pkgs.writeShellScriptBin "myshortcuts" ''
    echo "Shell aliases:"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: ''printf "  %-6s %s\n" "${name}" "${value}"'') aliases
    )}
    echo ""
    echo "Tmux (prefix is Ctrl-b):"
    printf "  %-14s %s\n" "Ctrl-b arrow" "switch pane in that direction"
    printf "  %-14s %s\n" "Ctrl-b o" "cycle to next pane"
    printf "  %-14s %s\n" "Ctrl-b q" "show pane numbers, then press one to jump"
    printf "  %-14s %s\n" "Ctrl-b \\" "split pane vertically (side by side)"
    printf "  %-14s %s\n" "Ctrl-b -" "split pane horizontally (stacked)"
    echo ""
    echo "wt (worktrunk, git worktrees):"
    printf "  %-24s %s\n" "wt switch --create x" "create worktree + branch \"x\" and switch to it"
    printf "  %-24s %s\n" "wt switch x" "switch to worktree \"x\""
    printf "  %-24s %s\n" "wt list" "list worktrees and their status"
    printf "  %-24s %s\n" "wt remove" "remove worktree; delete branch if merged"
    echo ""
    echo "hunk (diff viewer):"
    printf "  %-24s %s\n" "hunk diff" "review working tree changes"
    printf "  %-24s %s\n" "hunk diff --staged" "review staged changes"
    printf "  %-24s %s\n" "hunk diff --watch" "auto-reload as files change"
    printf "  %-24s %s\n" "hunk show" "review the latest commit"
    echo ""
    echo "herdr (agent multiplexer):"
    printf "  %-24s %s\n" "herdr" "launch or attach to the persistent session"
    printf "  %-24s %s\n" "Ctrl-b q" "detach (session keeps running)"
    printf "  %-24s %s\n" "herdr session attach x" "reattach to named session \"x\""
    echo ""
    echo "agents-init (per-project AGENTS.md/CLAUDE.md wiring):"
    printf "  %-14s %s\n" "agents-init" "create AGENTS.md + CLAUDE.md in cwd's repo, git-excluded locally"
  '';

  # Bootstraps a project's AGENTS.md/CLAUDE.md wiring without ever committing
  # either file to the project itself - these are personal, per-project notes
  # (not team-shared conventions), so they're kept out of the repo's own
  # .gitignore and excluded locally via .git/info/exclude instead.
  agentsInit = pkgs.writeShellScriptBin "agents-init" ''
    set -euo pipefail

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      echo "agents-init: not inside a git repository" >&2
      exit 1
    fi

    repo_root="$(git rev-parse --show-toplevel)"
    git_dir="$(git rev-parse --git-dir)"
    exclude_file="$git_dir/info/exclude"

    cd "$repo_root"

    if [ ! -e AGENTS.md ]; then
      cat > AGENTS.md <<'EOF'
    # Project Notes

    (empty - add project-specific conventions here as they're discovered)
    EOF
      echo "created AGENTS.md"
    else
      echo "AGENTS.md already exists, leaving it alone"
    fi

    if [ ! -e CLAUDE.md ]; then
      ln -s AGENTS.md CLAUDE.md
      echo "created CLAUDE.md -> AGENTS.md (symlink)"
    elif [ -L CLAUDE.md ] && [ "$(readlink CLAUDE.md)" = "AGENTS.md" ]; then
      echo "CLAUDE.md already symlinked to AGENTS.md"
    elif grep -qF '@AGENTS.md' CLAUDE.md 2>/dev/null; then
      echo "CLAUDE.md already imports AGENTS.md"
    else
      tmp="$(mktemp)"
      { echo "@AGENTS.md"; echo; cat CLAUDE.md; } > "$tmp"
      mv "$tmp" CLAUDE.md
      echo "added @AGENTS.md import to top of existing CLAUDE.md"
    fi

    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"
    for f in AGENTS.md CLAUDE.md; do
      if ! grep -qxF "$f" "$exclude_file"; then
        echo "$f" >> "$exclude_file"
        echo "excluded $f in .git/info/exclude"
      fi
    done
  '';

  # Wraps the three-way `herdr wait agent-status <pane> --status idle/blocked/done`
  # fan-out from the Delegation Workflow into one command. A worker pane can land
  # on any of those three terminal states and there's no single herdr status value
  # covering all of them - manually remembering to launch all three separately has
  # repeatedly led to one being forgotten (most recently `done`), leaving a stray
  # background wait running pointlessly. This runs all three, reports whichever
  # resolves first, and kills the other two - so there's nothing left to forget.
  herdrWaitAny = pkgs.writeShellScriptBin "herdr-wait-any" ''
    set -uo pipefail

    usage() {
      echo "usage: herdr-wait-any <pane_id> --timeout <ms>" >&2
    }

    pane_id=""
    timeout_ms=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --timeout)
          timeout_ms="''${2:-}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        -*)
          echo "herdr-wait-any: unknown option: $1" >&2
          usage
          exit 2
          ;;
        *)
          if [ -n "$pane_id" ]; then
            echo "herdr-wait-any: unexpected extra argument: $1" >&2
            usage
            exit 2
          fi
          pane_id="$1"
          shift
          ;;
      esac
    done

    if [ -z "$pane_id" ]; then
      echo "herdr-wait-any: missing required <pane_id>" >&2
      usage
      exit 2
    fi

    if [ -z "$timeout_ms" ]; then
      echo "herdr-wait-any: missing required --timeout" >&2
      usage
      exit 2
    fi

    statuses=(idle blocked done)
    work_dir="$(mktemp -d)"

    declare -A pid_for_status
    pids=()

    for status in "''${statuses[@]}"; do
      herdr wait agent-status "$pane_id" --status "$status" --timeout "$timeout_ms" \
        >"$work_dir/$status.out" 2>"$work_dir/$status.err" &
      pid=$!
      pid_for_status["$pid"]="$status"
      pids+=("$pid")
    done

    # Kills whatever's still running among the three sub-waits. Called both on the
    # happy path (once a status wins) and on any early exit (trap), so a killed or
    # interrupted wrapper never leaves a `herdr wait agent-status` process behind.
    cleanup_remaining() {
      for pid in "''${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
          kill "$pid" 2>/dev/null
        fi
      done
      for pid in "''${pids[@]}"; do
        wait "$pid" 2>/dev/null
      done
    }
    trap 'cleanup_remaining; rm -rf "$work_dir"' EXIT

    # INT/TERM interrupt the `wait -n` below at an arbitrary point; without an
    # explicit exit here, execution would fall back into the normal loop body and
    # report a bogus "no status resolved" against a work_dir that's already gone.
    on_signal() {
      echo "herdr-wait-any: interrupted" >&2
      exit 130
    }
    trap on_signal INT TERM

    winner_status=""
    remaining=("''${pids[@]}")

    while [ "''${#remaining[@]}" -gt 0 ]; do
      wait -n -p finished_pid "''${remaining[@]}" 2>/dev/null
      exit_code=$?

      # Bash leaves finished_pid unset if wait -n had nothing left to wait on;
      # guard rather than treat that as a match.
      if [ -z "''${finished_pid:-}" ]; then
        break
      fi

      status="''${pid_for_status[$finished_pid]}"

      new_remaining=()
      for pid in "''${remaining[@]}"; do
        if [ "$pid" != "$finished_pid" ]; then
          new_remaining+=("$pid")
        fi
      done
      remaining=("''${new_remaining[@]}")

      if [ "$exit_code" -eq 0 ]; then
        winner_status="$status"
        break
      fi

      unset finished_pid
    done

    if [ -n "$winner_status" ]; then
      echo "$winner_status"
      exit 0
    fi

    echo "herdr-wait-any: no status resolved for pane $pane_id within ''${timeout_ms}ms" >&2
    for status in "''${statuses[@]}"; do
      msg="$(tr -d '\n' <"$work_dir/$status.err" 2>/dev/null)"
      if [ -z "$msg" ]; then
        msg="$(tr -d '\n' <"$work_dir/$status.out" 2>/dev/null)"
      fi
      echo "  $status: ''${msg:-(no output)}" >&2
    done
    exit 1
  '';

  # `herdr-wait-any` is level-triggered: if a worker happens to already be
  # idle/blocked/done at the moment it's called (e.g. right after it
  # backgrounded a long subprocess and will flip back to working shortly),
  # it resolves instantly on that stale status instead of catching the
  # worker actually going back to work. That gives the orchestrator no
  # signal in exactly the case it needs one - it already knows from the
  # worker's last message that it isn't really done. This wraps
  # `herdr-wait-any` with a deterministic pre-check: if the pane is
  # currently idle/blocked/done, first block until it's observed `working`
  # (proof it actually left that state) before delegating to
  # `herdr-wait-any` for the real settle. If the worker never leaves its
  # starting state within the timeout, that's a distinct "no progress"
  # outcome (`still-<status>`, exit 3) from a normal settle - the caller
  # can tell "nothing happened" apart from "it settled".
  herdrWaitSettle = pkgs.writeShellScriptBin "herdr-wait-settle" ''
    set -uo pipefail

    usage() {
      echo "usage: herdr-wait-settle <pane_id> --timeout <ms>" >&2
    }

    pane_id=""
    timeout_ms=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --timeout)
          timeout_ms="''${2:-}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        -*)
          echo "herdr-wait-settle: unknown option: $1" >&2
          usage
          exit 2
          ;;
        *)
          if [ -n "$pane_id" ]; then
            echo "herdr-wait-settle: unexpected extra argument: $1" >&2
            usage
            exit 2
          fi
          pane_id="$1"
          shift
          ;;
      esac
    done

    if [ -z "$pane_id" ]; then
      echo "herdr-wait-settle: missing required <pane_id>" >&2
      usage
      exit 2
    fi

    if [ -z "$timeout_ms" ]; then
      echo "herdr-wait-settle: missing required --timeout" >&2
      usage
      exit 2
    fi

    on_signal() {
      echo "herdr-wait-settle: interrupted" >&2
      exit 130
    }
    trap on_signal INT TERM

    current_status="$(herdr agent get "$pane_id" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.result.agent.agent_status // empty')"
    if [ -z "$current_status" ]; then
      echo "herdr-wait-settle: could not determine current status for pane $pane_id" >&2
      exit 1
    fi

    case "$current_status" in
      idle|blocked|done)
        if ! herdr wait agent-status "$pane_id" --status working --timeout "$timeout_ms" >/dev/null 2>&1; then
          echo "herdr-wait-settle: still-$current_status (pane $pane_id never left $current_status to start working within ''${timeout_ms}ms)" >&2
          exit 3
        fi
        ;;
    esac

    exec ${herdrWaitAny}/bin/herdr-wait-any "$pane_id" --timeout "$timeout_ms"
  '';

  # Replaces the Delegation Workflow's manual send-text/sleep/send-keys/verify
  # dance (the paste-race workaround for long task text swallowing Enter) with
  # a single verified call. Ported from firstmate's proven herdr adapter
  # (~/.bosun/firstmate-home/bin/backends/herdr.sh, fm_backend_herdr_send_text_submit):
  # type the text once (unsubmitted), capture the pane as a baseline, then
  # retry Enter-only (never retype) until the capture visibly changes from
  # that baseline. Only a capture that never changes after all retries is a
  # confirmed swallow (exit 1); this is strictly better than a fixed sleep
  # guess, since it retries automatically and reports a real error instead of
  # silently leaving unsent text sitting in the composer.
  herdrSendVerified = pkgs.writeShellScriptBin "herdr-send-verified" ''
    set -uo pipefail

    usage() {
      echo "usage: herdr-send-verified <pane_id> <text...>" >&2
      echo "       herdr-send-verified <pane_id> --key <Enter|Escape|ctrl+c>" >&2
    }

    PANE_ID="''${1:-}"
    if [ -z "$PANE_ID" ]; then
      usage
      exit 2
    fi
    shift

    normalize_key() {
      case "$1" in
        Enter|enter) echo enter ;;
        Escape|escape|Esc|esc) echo escape ;;
        C-c|c-c|ctrl+c|Ctrl+C) echo "ctrl+c" ;;
        *) echo "$1" ;;
      esac
    }

    # Bounded pane capture. herdr's own `pane read --lines N` returns COMPLETELY
    # EMPTY output (not a clamped result) when N is smaller than the pane's
    # current viewport height (~23 rows for a default pane) - verified upstream
    # in firstmate's docs/herdr-backend.md. Always request a generous floor and
    # trim locally with `tail` instead of trusting a small --lines straight through.
    capture() {
      local lines="''${1:-6}" out
      out=$(herdr pane read "$PANE_ID" --source recent --lines 200 2>/dev/null) || return 1
      printf '%s' "$out" | tail -n "$lines"
    }

    if [ "''${1:-}" = "--key" ]; then
      key=$(normalize_key "''${2:-Enter}")
      if ! herdr pane send-keys "$PANE_ID" "$key" >/dev/null 2>&1; then
        echo "error: failed to send key '$key' to pane $PANE_ID" >&2
        exit 1
      fi
      exit 0
    fi

    TEXT="$*"
    if [ -z "$TEXT" ]; then
      usage
      exit 2
    fi

    # Slash commands (and codex `$<skill>` invocations) open a completion popup in
    # some TUIs; submitting too fast selects nothing. Give popups time to settle
    # before the (retried) Enter below.
    case "$TEXT" in
      /*|\$*) SETTLE="''${HERDR_SEND_SETTLE:-1.2}" ;;
      *) SETTLE="''${HERDR_SEND_SETTLE:-0.3}" ;;
    esac
    RETRIES="''${HERDR_SEND_RETRIES:-5}"
    SLEEP_S="''${HERDR_SEND_SLEEP:-0.4}"

    if ! herdr pane send-text "$PANE_ID" "$TEXT" >/dev/null 2>&1; then
      echo "error: text not sent to pane $PANE_ID (herdr pane send-text failed)" >&2
      exit 1
    fi

    sleep "$SETTLE"
    if ! typed=$(capture 6); then
      echo "error: pane $PANE_ID unreadable after send; cannot verify submit" >&2
      exit 1
    fi

    i=0
    while :; do
      herdr pane send-keys "$PANE_ID" enter >/dev/null 2>&1 || true
      sleep "$SLEEP_S"
      if ! after=$(capture 6); then
        echo "error: pane $PANE_ID became unreadable mid-retry; cannot verify submit" >&2
        exit 1
      fi
      if [ "$after" != "$typed" ]; then
        exit 0
      fi
      i=$((i + 1))
      if [ "$i" -ge "$RETRIES" ]; then
        echo "error: text not submitted to pane $PANE_ID (Enter swallowed; text left in composer after $RETRIES retries)" >&2
        exit 1
      fi
    done
  '';

  # Replaces the Delegation Workflow's manual `herdr tab create --workspace
  # ... --cwd ... --label ...` step, whose known failure mode is a caller
  # omitting --workspace and landing the tab in whatever workspace currently
  # has UI focus (possibly someone else's session). Ported from firstmate's
  # fm_backend_herdr_workspace_ensure + fm_backend_herdr_create_task
  # (~/.bosun/firstmate-home/bin/backends/herdr.sh): find-or-create the
  # workspace by a stable label instead of assuming it already exists, and
  # refuse a duplicate tab label instead of silently creating a second one
  # (herdr enforces no label uniqueness itself for either workspaces or tabs).
  # One workspace per PROJECT (not per worktree, since worktrees are
  # transient per delegated branch): the label is derived from the project's
  # own primary checkout via `git rev-parse --git-common-dir`, which always
  # resolves to the primary .git even when called from inside a worktree, so
  # every worker for a project lands as a tab in that same one workspace.
  herdrSpawnTab = pkgs.writeShellScriptBin "herdr-spawn-tab" ''
    set -uo pipefail

    usage() {
      echo "usage: herdr-spawn-tab <label> <cwd>" >&2
    }

    LABEL="''${1:-}"
    CWD="''${2:-}"
    if [ -z "$LABEL" ] || [ -z "$CWD" ]; then
      usage
      exit 2
    fi

    if [ ! -d "$CWD" ]; then
      echo "error: cwd $CWD does not exist" >&2
      exit 1
    fi

    command -v jq >/dev/null 2>&1 || { echo "error: jq is required to parse herdr's JSON output" >&2; exit 1; }

    GIT_COMMON_DIR=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [ -z "$GIT_COMMON_DIR" ]; then
      echo "error: $CWD is not inside a git repository (cannot derive a workspace label)" >&2
      exit 1
    fi
    PROJ_LABEL=$(basename "$(dirname "$GIT_COMMON_DIR")")
    if [ -z "$PROJ_LABEL" ]; then
      echo "error: could not derive a project label from $CWD" >&2
      exit 1
    fi

    # Find-before-create: never assume the workspace already exists (the known
    # failure mode this replaces - a caller omitting --workspace and landing the
    # tab in whatever workspace currently has UI focus).
    WORKSPACE_ID=$(herdr workspace list 2>/dev/null | jq -r --arg label "$PROJ_LABEL" \
      '.result.workspaces[]? | select(.label == $label) | .workspace_id' | head -1)

    if [ -z "$WORKSPACE_ID" ]; then
      CREATE_OUT=$(herdr workspace create --cwd "$CWD" --label "$PROJ_LABEL" --no-focus 2>/dev/null)
      if [ -z "$CREATE_OUT" ]; then
        echo "error: failed to create herdr workspace '$PROJ_LABEL'" >&2
        exit 1
      fi
      WORKSPACE_ID=$(printf '%s' "$CREATE_OUT" | jq -r '.result.workspace.workspace_id // empty')
      if [ -z "$WORKSPACE_ID" ]; then
        echo "error: could not parse workspace_id from herdr workspace create output" >&2
        exit 1
      fi
    fi

    # herdr enforces no label uniqueness itself - two tabs (or two workspaces)
    # can share a label - so the duplicate check is ours, matching the
    # find-before-create workspace lookup above.
    DUP=$(herdr tab list --workspace "$WORKSPACE_ID" 2>/dev/null | jq -r --arg label "$LABEL" \
      '.result.tabs[]? | select(.label == $label) | .tab_id' | head -1)
    if [ -n "$DUP" ]; then
      echo "error: herdr tab '$LABEL' already exists in workspace $WORKSPACE_ID ($PROJ_LABEL) - refusing to create a duplicate" >&2
      exit 1
    fi

    TAB_OUT=$(herdr tab create --workspace "$WORKSPACE_ID" --cwd "$CWD" --label "$LABEL" --no-focus 2>/dev/null)
    if [ -z "$TAB_OUT" ]; then
      echo "error: herdr tab create failed for label $LABEL in workspace $WORKSPACE_ID" >&2
      exit 1
    fi

    TAB_ID=$(printf '%s' "$TAB_OUT" | jq -r '.result.tab.tab_id // empty')
    PANE_ID=$(printf '%s' "$TAB_OUT" | jq -r '.result.root_pane.pane_id // empty')

    if [ -z "$TAB_ID" ] || [ -z "$PANE_ID" ]; then
      echo "error: could not parse tab/pane id from herdr tab create output" >&2
      exit 1
    fi

    echo "$TAB_ID $PANE_ID"
  '';

  # Mechanizes the Delegation Workflow's index.md trim step: once
  # .claude/delegation/index.md grows past --keep (default 20) entries, drop
  # the oldest down to that count, deleting each dropped entry's <branch>.md
  # in the same step (a matched deletion, not an archive - index.md should
  # never point at a plan file that no longer exists, and no plan file should
  # outlive its roster line). Doing this by hand via ad hoc file edits is
  # exactly the kind of bookkeeping that hides a dangling-reference bug; this
  # is a no-op below the threshold, so it is safe to run unconditionally.
  # No brigade/firstmate equivalent - their tracker is tickets.toml/
  # no-mistakes-backed, not the markdown table this repo's own delegation
  # workflow uses, so this one is novel rather than ported.
  delegationIndexTrim = pkgs.writeShellScriptBin "delegation-index-trim" ''
    set -uo pipefail

    usage() {
      echo "usage: delegation-index-trim [--keep N]  (default N=20)" >&2
    }

    KEEP=20
    while [ $# -gt 0 ]; do
      case "$1" in
        --keep)
          KEEP="''${2:-}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          echo "delegation-index-trim: unknown argument: $1" >&2
          usage
          exit 2
          ;;
      esac
    done

    if ! [[ "$KEEP" =~ ^[0-9]+$ ]]; then
      echo "delegation-index-trim: --keep requires a positive integer, got: '$KEEP'" >&2
      exit 2
    fi

    INDEX=".claude/delegation/index.md"
    if [ ! -f "$INDEX" ]; then
      echo "delegation-index-trim: no $INDEX in $(pwd) - nothing to trim"
      exit 0
    fi

    mapfile -t LINES < <(grep -v '^[[:space:]]*$' "$INDEX")
    TOTAL="''${#LINES[@]}"

    if [ "$TOTAL" -le "$KEEP" ]; then
      echo "delegation-index-trim: $TOTAL entries, within --keep $KEEP - no trim needed"
      exit 0
    fi

    DROP_COUNT=$((TOTAL - KEEP))
    DROPPED=("''${LINES[@]:0:$DROP_COUNT}")
    KEPT=("''${LINES[@]:$DROP_COUNT}")

    for line in "''${DROPPED[@]}"; do
      # Plan paths always live under .claude/delegation/ - anchor on that rather
      # than assuming a fixed pipe-field position, since goal/status text is
      # free-form and could itself contain a literal "|".
      plan_path=$(printf '%s\n' "$line" | grep -oE '\.claude/delegation/[^ |]+\.md' | head -1)
      if [ -n "$plan_path" ] && [ -f "$plan_path" ]; then
        rm -f -- "$plan_path"
        echo "delegation-index-trim: dropped $plan_path"
      fi
    done

    printf '%s\n' "''${KEPT[@]}" > "$INDEX"
    echo "delegation-index-trim: trimmed $DROP_COUNT entries, kept $KEEP"
  '';

  # Mechanizes the Delegation Workflow's teardown step: close the worker's
  # herdr tab, and remove its worktree unless it was already self-removed
  # (e.g. the worker already ran `wt merge`, which removes its own worktree
  # and branch as part of the same command). --tab and the worktree-gone
  # check both auto-fall-back to the worker's own
  # .claude/delegation/<branch>.md header (its recorded tab:/worktree:
  # fields) when not given explicitly, so the common case needs only the
  # branch name; --tab and --worktree-gone remain available to override or
  # to cover a missing/stale plan file.
  delegationCleanup = pkgs.writeShellScriptBin "delegation-cleanup" ''
    set -uo pipefail

    usage() {
      echo "usage: delegation-cleanup <branch> [--tab <tab_id>] [--worktree-gone]" >&2
    }

    BRANCH=""
    TAB_ID=""
    WORKTREE_GONE=0

    while [ $# -gt 0 ]; do
      case "$1" in
        --tab)
          TAB_ID="''${2:-}"
          shift 2
          ;;
        --worktree-gone)
          WORKTREE_GONE=1
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        -*)
          echo "delegation-cleanup: unknown option: $1" >&2
          usage
          exit 2
          ;;
        *)
          if [ -n "$BRANCH" ]; then
            echo "delegation-cleanup: unexpected extra argument: $1" >&2
            usage
            exit 2
          fi
          BRANCH="$1"
          shift
          ;;
      esac
    done

    if [ -z "$BRANCH" ]; then
      usage
      exit 2
    fi

    PLAN_FILE=".claude/delegation/$BRANCH.md"

    # --tab is optional: fall back to the tab id recorded in the worker's own
    # plan file header, so a caller doesn't have to keep it around separately.
    if [ -z "$TAB_ID" ] && [ -f "$PLAN_FILE" ]; then
      TAB_ID=$(grep -m1 '^tab:' "$PLAN_FILE" | sed 's/^tab:[[:space:]]*//')
    fi

    # Auto-detect an already-self-removed worktree (e.g. the worker already ran
    # `wt merge`, which removes its own worktree and branch) from the plan
    # file's recorded worktree path, unless --worktree-gone already said so.
    if [ "$WORKTREE_GONE" -eq 0 ] && [ -f "$PLAN_FILE" ]; then
      WT_PATH=$(grep -m1 '^worktree:' "$PLAN_FILE" | sed 's/^worktree:[[:space:]]*//')
      if [ -n "$WT_PATH" ] && [ ! -d "$WT_PATH" ]; then
        echo "delegation-cleanup: worktree $WT_PATH already gone (self-removed, e.g. by wt merge) - skipping wt remove"
        WORKTREE_GONE=1
      fi
    fi

    if [ "$WORKTREE_GONE" -eq 0 ]; then
      echo "delegation-cleanup: removing worktree for branch $BRANCH"
      wt remove "$BRANCH"
    else
      echo "delegation-cleanup: worktree already gone, not calling wt remove"
    fi

    if [ -n "$TAB_ID" ]; then
      echo "delegation-cleanup: closing herdr tab $TAB_ID"
      if ! herdr tab close "$TAB_ID" >/dev/null 2>&1; then
        echo "delegation-cleanup: warning: herdr tab close $TAB_ID failed (already closed?)" >&2
      fi
    else
      echo "delegation-cleanup: warning: no tab id given or recorded in $PLAN_FILE - not closing any herdr tab" >&2
    fi

    echo "delegation-cleanup: done for branch $BRANCH"
  '';

  # wezterm needs GPU/EGL access that nix can't see on a non-NixOS Linux
  # host, so wrap it with nixGL (auto-detects Nvidia vs. Mesa) to pick up
  # the system's real drivers. Not needed on macOS, where wezterm talks to
  # Metal directly.
  weztermPackages =
    if isLinux then
      [
        (pkgs.writeShellScriptBin "wezterm" ''
          exec ${pkgs.nixgl.auto.nixGLDefault}/bin/nixGL ${pkgs.wezterm}/bin/wezterm "$@"
        '')
        (pkgs.writeShellScriptBin "wezterm-gui" ''
          exec ${pkgs.nixgl.auto.nixGLDefault}/bin/nixGL ${pkgs.wezterm}/bin/wezterm-gui "$@"
        '')
      ]
    else
      [ pkgs.wezterm ];
in
{
  home.username = username;
  home.homeDirectory = if isLinux then "/home/${username}" else "/Users/${username}";

  # Bump when moving to a newer home-manager release; do not change on a whim.
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings.user = {
      name = "Bryson Bailey";
      email = "brysonbailey94@gmail.com";
    };
  };

  # Review-first terminal diff viewer; invoked explicitly (`hunk diff`,
  # `hunk show`) rather than replacing git's default pager, so plain
  # `git diff`/`git show` output stays plain text for scripts and agents.
  programs.hunk.enable = true;

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = aliases;

    initContent = ''
      bindkey '^f' autosuggest-accept
      eval "$(mise activate zsh)"
      eval "$(wt config shell init zsh)"
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings.git_protocol = "ssh";
  };

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    mouse = true;
    extraConfig = ''
      unbind %
      bind '\' split-window -h -c "#{pane_current_path}"
      unbind '"'
      bind - split-window -v -c "#{pane_current_path}"
    '';
  };

  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    eza
    neovim
    nerd-fonts.hack
    claude-code
    jq
    mise
    myshortcuts
    worktrunk
    herdr
    agentsInit
    herdrWaitAny
    herdrWaitSettle
    herdrSendVerified
    herdrSpawnTab
    delegationIndexTrim
    delegationCleanup
  ] ++ weztermPackages;
  fonts.fontconfig.enable = true;

  # home-manager's font handling is Linux-oriented (fontconfig); macOS apps
  # read fonts straight from ~/Library/Fonts via CoreText instead, so link
  # the nix-installed nerd font there too.
  home.activation.installNerdFontOnDarwin = lib.mkIf (!isLinux) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$HOME/Library/Fonts"
      $DRY_RUN_CMD find ${pkgs.nerd-fonts.hack}/share/fonts -type f \( -name '*.ttf' -o -name '*.otf' \) -exec ${pkgs.coreutils}/bin/ln -sf {} "$HOME/Library/Fonts/" \;
    ''
  );

  # macOS occasionally resets "Automatically hide and show the menu bar" on
  # its own (known behavior after waking from sleep or changing displays).
  # Not a nix-darwin box, so home-manager can't declare system.defaults;
  # reapplying it as a plain `defaults write` on every switch is the
  # equivalent self-healing fix.
  home.activation.hideMenuBarOnDarwin = lib.mkIf (!isLinux) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD /usr/bin/defaults write NSGlobalDomain _HIHideMenuBar -bool true
      $DRY_RUN_CMD /usr/bin/killall SystemUIServer || true
    ''
  );

  # Caps Lock -> Escape, mainly for vim. Went through the desktop's own
  # keyboard-settings gsettings key first (org.cinnamon.desktop.input-sources
  # xkb-options), but confirmed on the actual machine that Cinnamon's
  # settings daemon (csd-keyboard) never applies that key to the live X
  # server, even right after a fresh daemon respawn with the value already
  # set. An XDG autostart entry calling setxkbmap directly is what actually
  # works (verified live): it's DE-agnostic (any X11 session honors XDG
  # autostart) and additive (`-option`, not `-options`, layers onto
  # whatever options the system already sets rather than replacing them).
  home.file.".config/autostart/remap-capslock-escape.desktop" = lib.mkIf isLinux {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Remap Caps Lock to Escape
      Exec=sh -c 'command -v setxkbmap >/dev/null 2>&1 && setxkbmap -option caps:escape'
      X-GNOME-Autostart-enabled=true
      NoDisplay=true
    '';
  };

  # Registers herdr's Claude Code integration hook (~/.claude/hooks/herdr-agent-state.sh
  # + the SessionStart entry in claude/settings.json) so herdr's own agent-status
  # tracking (idle/working/blocked) works for Claude Code workers spawned by the
  # Delegation Workflow - reapplied every switch since it's idempotent and this is
  # how the hook script itself gets (re)written on a new machine.
  home.activation.installHerdrClaudeIntegration = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr integration install claude
  '';

  # Worktrunk user hook: wires AGENTS.md/CLAUDE.md into every new worktree via
  # agents-init, ahead of any project-level hooks. Was a hand-edited local file
  # (it used to also carry unrelated Bosun hooks); safe to manage declaratively
  # now that it's just this one line.
  home.file.".config/worktrunk/config.toml".text = ''
    [pre-start]
    agents-init = "agents-init"
  '';

  home.file.".config/herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/herdr/config.toml";

  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/wezterm";

  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/nvim";

  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/claude/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/AGENTS.md";

  # The `delegate` skill (mechanizes the Delegation Workflow's worker-spawn
  # mechanics) and its worker-launch template - global, like the Delegation
  # Workflow prose in AGENTS.md it replaces, not project-scoped.
  home.file.".claude/skills/delegate/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/claude/skills/delegate/SKILL.md";

  home.file.".claude/skills/delegate/worker-launch-template.txt".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/claude/skills/delegate/worker-launch-template.txt";

  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/AGENTS.md";

  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/AGENTS.md";

  # pi has no native global-instructions mechanism today (would need a
  # third-party memory extension with its own non-AGENTS.md storage format) -
  # deliberately not wired here, not an oversight.

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
