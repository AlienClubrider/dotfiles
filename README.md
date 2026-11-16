# dotfiles

My terminal setup for macOS: WezTerm, Neovim, zsh (with Starship, autosuggestions,
syntax highlighting and fzf) and a handful of command-line tools. Tools come from
Homebrew; configs are plain files that get **copied** into place (no symlinks, no Nix).

## What's here

| Path | Goes to | What it is |
| --- | --- | --- |
| `wezterm/` | `~/.config/wezterm/` | WezTerm: rose-pine-moon, Hack Nerd Font, 80% opacity, starts maximized |
| `nvim/` | `~/.config/nvim/` | Neovim (lazy.nvim, snacks, oil, which-key, neogit, gitsigns, diffview) |
| `zsh/zshrc` | `~/.zshrc` | Shell setup, `myshortcuts` command, Ctrl-F to accept suggestions |
| `zsh/aliases.zsh` | `~/.config/zsh/aliases.zsh` | Shell aliases (`ll`, `gs`, `vim`, ...) |
| `starship/starship.toml` | `~/.config/starship.toml` | Prompt |
| `Brewfile` | — | Every tool and font to install |
| `install.sh` | — | Installs the Brewfile and copies the configs |

## Set up a new Mac

1. Install [Homebrew](https://brew.sh).
2. Clone and install:

   ```sh
   git clone https://github.com/AlienClubrider/dotfiles.git ~/dev/dotfiles
   cd ~/dev/dotfiles
   ./install.sh
   ```

3. Set Caps Lock to Escape (macOS doesn't let a script do this cleanly):
   **System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys → Caps Lock → Escape**.

`install.sh` backs up any existing file it would replace as `<name>.bak-<timestamp>`.

## Making changes

Edit files in this repo, then run `./install.sh --no-brew` to copy them over
(drop `--no-brew` if you changed the `Brewfile`). Then commit and push as usual.

## Everyday use

Run `myshortcuts` to list your aliases and key bindings.
