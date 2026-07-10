# dotfiles

Reproducible dev environment managed with [Nix](https://nixos.org) +
[home-manager](https://nix-community.github.io/home-manager/): shell (zsh +
starship), git/gh, fzf, and config for WezTerm and Neovim (lazy.nvim,
snacks.nvim, oil.nvim, neogit, gitsigns, which-key).

No system-level manager (nix-darwin/NixOS) is used here — everything lives
in the user's home directory, so this works the same way on a fresh macOS
or Linux machine.

## Structure

- `flake.nix` / `flake.lock` — pins the exact package versions (nixpkgs +
  home-manager) so a rebuild years from now installs the same thing it did
  today.
- `home.nix` — the actual config: packages, zsh, starship, git, gh, fzf,
  and the symlinks that wire `wezterm/` and `nvim/` into `~/.config`.
- `wezterm/`, `nvim/` — plain config files for those two apps, edited
  in place (see below).
- `bootstrap.sh` — one-time setup on a new machine.
- `rebuild.sh` — re-run any time `home.nix` changes.

## Using this on a brand new machine

Works unmodified on both macOS (Apple Silicon or Intel) and Linux — the
flake detects the current system and username at switch time (via
`--impure`, see below), so there's nothing to edit first. Clone the repo
anywhere you like and run the bootstrap script:

```sh
git clone git@github.com:AlienClubrider/dotfiles.git
cd dotfiles
./bootstrap.sh
```

`bootstrap.sh` will:

1. Install Nix (via the [Determinate Systems installer](https://determinate.systems/nix-installer/)) if it isn't already present.
2. Symlink the repo to `~/.dotfiles` — a stable path that `home.nix` uses
   to find `wezterm/` and `nvim/`, regardless of where you actually cloned
   the repo.
3. Run the first `home-manager switch`, which installs every package and
   config declared in `home.nix`.
4. Make zsh your login shell (this needs your password, since only root
   can change `/etc/shells` — everything else runs unprivileged).

Log out and back in (or reboot) afterward so the new login shell takes
effect.

If you already have a `~/.zshrc` (or other files home-manager wants to
manage), move it aside first — e.g. `mv ~/.zshrc ~/.zshrc.bak` — since
home-manager refuses to overwrite files it doesn't already own.

### Why `--impure`

`flake.nix` reads the current system (`builtins.currentSystem`) and user
(`$USER`) at evaluation time instead of hardcoding them, which is what
lets the same flake work on any machine unedited. Both are impure by Nix's
definition (their value depends on where you run it), so `bootstrap.sh`
and `rebuild.sh` both pass `--impure`. Everything else about the config is
still fully pinned by `flake.lock`.

### macOS notes

- `wezterm` runs straight from nixpkgs — no wrapper needed, since it talks
  to Metal directly instead of needing Linux's EGL/GL stack.
- The nerd font gets symlinked into `~/Library/Fonts` automatically on
  activation, since macOS apps read fonts via CoreText rather than
  fontconfig.

### Linux notes

- `wezterm` is wrapped with [nixGL](https://github.com/nix-community/nixGL)
  (`nixGLDefault`, which auto-detects Nvidia vs. Mesa at switch time).
  Nix-built GUI apps can't see a non-NixOS host's GPU drivers on their
  own, so without this wrapper wezterm fails to open a window with an EGL
  error.

## Everyday use

Run `myshortcuts` any time to print the full list of shell aliases this
config sets up (`ll`, `gs`, `ta`, etc.) — it's generated straight from
`home.nix`, so it never drifts out of date.

## Making changes later

- **Editing `home.nix`** (packages, zsh, starship, git/gh config): after
  editing, run `./rebuild.sh` to apply it.
- **Editing `wezterm/wezterm.lua` or anything under `nvim/`**: these are
  live-symlinked into `~/.config`, so changes take effect immediately —
  WezTerm hot-reloads its config, and Neovim picks up changes the next
  time it starts. No rebuild needed.

Commit and push changes the normal way (`git add`, `git commit`,
`git push`) to keep GitHub in sync.
