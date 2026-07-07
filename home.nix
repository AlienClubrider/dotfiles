{ pkgs, config, ... }:

{
  home.username = "johanna";
  home.homeDirectory = "/home/johanna";

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

    shellAliases = {
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
    };

    initContent = ''
      bindkey '^f' autosuggest-accept
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

  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    eza
    wezterm
    neovim
    nerd-fonts.hack
    herdr
    claude-code
  ];
  fonts.fontconfig.enable = true;

  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/wezterm";

  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/nvim";

  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/herdr";

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
