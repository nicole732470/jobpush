#!/bin/zsh
set -e
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

PKG_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg"
PKG_PATH="/tmp/session-manager-plugin.pkg"

if command -v session-manager-plugin >/dev/null 2>&1; then
  echo "Session Manager plugin is already installed:"
  session-manager-plugin --version
  read "?Press Enter to close..."
  exit 0
fi

echo "Downloading Session Manager plugin..."
curl -fsSL "$PKG_URL" -o "$PKG_PATH"

echo "Opening the macOS installer. Follow the prompts, then retry open-database.command."
open "$PKG_PATH"

read "?Press Enter to close..."
