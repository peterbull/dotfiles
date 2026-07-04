#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$HOME"
VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"

echo "==> Setting up VS Code symlinks..."

mkdir -p "$VSCODE_USER_DIR"

if [ -e "$VSCODE_USER_DIR/settings.json" ] && [ ! -L "$VSCODE_USER_DIR/settings.json" ]; then
  echo "Backing up existing settings.json"
  mv "$VSCODE_USER_DIR/settings.json" "$VSCODE_USER_DIR/settings.json.bak.$(date +%s)"
fi
ln -sf "$DOTFILES_DIR/.vscode/settings.json" "$VSCODE_USER_DIR/settings.json"
echo "Linked settings.json"

if [ -e "$VSCODE_USER_DIR/keybindings.json" ] && [ ! -L "$VSCODE_USER_DIR/keybindings.json" ]; then
  echo "Backing up existing keybindings.json"
  mv "$VSCODE_USER_DIR/keybindings.json" "$VSCODE_USER_DIR/keybindings.json.bak.$(date +%s)"
fi
ln -sf "$DOTFILES_DIR/.vscode/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"
echo "Linked keybindings.json"

echo "==> Verifying symlinks..."
ls -la "$VSCODE_USER_DIR/settings.json" "$VSCODE_USER_DIR/keybindings.json"

echo "==> Done."
