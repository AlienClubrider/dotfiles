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

Works on both macOS and Linux, with two lines in the repo you edit first
depending on which:

1. In `flake.nix`, set `system` to match your machine:
   - Linux: `x86_64-linux`
   - Mac (Apple Silicon): `aarch64-darwin`
   - Mac (Intel): `x86_64-darwin`
2. In `home.nix`, set `home.username` and `home.homeDirectory`:
   - Linux: `/home/<username>`
   - Mac: `/Users/<username>`

Then clone the repo anywhere you like and run the bootstrap script:

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

## Making changes later

- **Editing `home.nix`** (packages, zsh, starship, git/gh config): after
  editing, run `./rebuild.sh` to apply it.
- **Editing `wezterm/wezterm.lua` or anything under `nvim/`**: these are
  live-symlinked into `~/.config`, so changes take effect immediately —
  WezTerm hot-reloads its config, and Neovim picks up changes the next
  time it starts. No rebuild needed.

Commit and push changes the normal way (`git add`, `git commit`,
`git push`) to keep GitHub in sync.
