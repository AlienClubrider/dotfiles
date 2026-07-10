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

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = aliases;

    initContent = ''
      bindkey '^f' autosuggest-accept
      eval "$(mise activate zsh)"
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

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
