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

  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/wezterm";

  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/nvim";

  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/claude/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/AGENTS.md";

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
