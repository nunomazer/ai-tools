#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/claude-loop.sh"

# Symlink into a stable, PATH-resolved location. ~/.local/bin is where the
# claude CLI itself lives, so it's guaranteed on PATH for the same shell.
BIN_DIR="${CLAUDE_LOOP_BIN_DIR:-$HOME/.local/bin}"
LINK="$BIN_DIR/claude-loop"

echo "=== claude-loop Installer ==="
echo "Source: $SOURCE"
echo "Link:   $LINK"
echo ""

chmod +x "$SOURCE"
mkdir -p "$BIN_DIR"
ln -sf "$SOURCE" "$LINK"
echo "Linked: $LINK -> $SOURCE"

if ! echo ":$PATH:" | grep -q ":$BIN_DIR:"; then
    echo ""
    echo "WARNING: $BIN_DIR is not on your PATH. Add this to your ~/.zshrc:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ai-tools/claude-loop"
mkdir -p "$CONFIG_DIR"
echo ""
echo "Config dir: $CONFIG_DIR"
echo "Configure accounts (paths stay local, never committed):"
echo "  claude-loop --add-account <name> --config-dir <CLAUDE_CONFIG_DIR>"
echo "See claude-loop/accounts.example for the file format."
echo ""
echo "Done! Run: claude-loop --help"
