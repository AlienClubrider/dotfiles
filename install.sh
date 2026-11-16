#!/usr/bin/env bash
# Installs the Brewfile tools and copies these configs into place (no symlinks).
# Safe to re-run any time you edit something in this repo.
# Usage: ./install.sh            install tools + copy configs
#        ./install.sh --no-brew  only copy configs
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [ "${1:-}" != "--no-brew" ]; then
  if ! command -v brew >/dev/null; then
    echo "Homebrew isn't installed. Get it from https://brew.sh, then re-run this." >&2
    exit 1
  fi
  echo "==> Installing tools from Brewfile"
  brew bundle --file="$DIR/Brewfile"
fi

# copy <source> <dest>: backs up anything already there that isn't identical
copy() {
  local src="$1" dest="$2"
  if [ -L "$dest" ]; then
    rm "$dest"   # old symlink from the Nix setup
  elif [ -e "$dest" ]; then
    if diff -rq "$src" "$dest" >/dev/null 2>&1; then
      echo "    unchanged: $dest"; return
    fi
    mv "$dest" "$dest.bak-$STAMP"
    echo "    backed up old $dest to $dest.bak-$STAMP"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
  echo "    copied: $dest"
}

echo "==> Copying configs"
copy "$DIR/wezterm"                 "$CONFIG/wezterm"
copy "$DIR/nvim"                    "$CONFIG/nvim"
copy "$DIR/starship/starship.toml"  "$CONFIG/starship.toml"
copy "$DIR/zsh/aliases.zsh"         "$CONFIG/zsh/aliases.zsh"
copy "$DIR/zsh/zshrc"               "$HOME/.zshrc"

echo "==> Done. Open a new terminal (or run: exec zsh) to load the shell changes."
