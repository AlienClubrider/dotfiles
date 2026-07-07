#!/usr/bin/env bash
# Takes a fresh Linux machine from nothing to a built home-manager config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> Step 1: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: first home-manager switch"
# The home-manager command doesn't exist yet on a fresh machine, so run it
# straight from the flake this once. After this, rebuild.sh works normally.
nix run home-manager/master -- switch --flake ~/.dotfiles#bryson

echo "==> Step 4: make zsh the login shell"
# home-manager runs unprivileged and can't touch /etc/passwd or /etc/shells,
# so this is the one piece it can never do for us - only root can.
ZSH_PATH="$(command -v zsh)"
if [ "${SHELL:-}" = "$ZSH_PATH" ]; then
  echo "    zsh is already the login shell, skipping"
else
  if ! grep -qxF "$ZSH_PATH" /etc/shells; then
    echo "    registering $ZSH_PATH in /etc/shells (needs sudo)"
    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  fi
  echo "    setting $ZSH_PATH as your login shell (needs your password)"
  chsh -s "$ZSH_PATH"
fi

echo "==> Done. Log out and back in (or reboot) so the new login shell takes effect."
echo "    Use ./rebuild.sh for future changes."
