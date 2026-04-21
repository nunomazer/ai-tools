#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE="$SCRIPT_DIR/statusline.py"

# When CLAUDE_CONFIG_DIR is set, settings.json lives there and the wrapper
# is named per-account so concurrent accounts don't overwrite each other.
# Wrappers always live in ~/.claude/ because it's a stable, shared location
# (the Linux home is per-user, while CLAUDE_CONFIG_DIR may point anywhere,
# including cloud-synced folders where exec perms can be flaky).
WRAPPER_DIR="$HOME/.claude"

if [ -n "$CLAUDE_CONFIG_DIR" ]; then
    CONFIG_DIR="$CLAUDE_CONFIG_DIR"
    ACCOUNT_SLUG="$(basename "$CLAUDE_CONFIG_DIR")"
    WRAPPER="$WRAPPER_DIR/statusline-wrapper-$ACCOUNT_SLUG.sh"
else
    CONFIG_DIR="$HOME/.claude"
    WRAPPER="$WRAPPER_DIR/statusline-wrapper.sh"
fi

SETTINGS="$CONFIG_DIR/settings.json"

echo "=== Claude Statusline Installer ==="
echo "Config dir: $CONFIG_DIR"
echo "Wrapper:    $WRAPPER"
echo "Statusline: $STATUSLINE"
echo ""

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not found."
    exit 1
fi

mkdir -p "$WRAPPER_DIR"
mkdir -p "$CONFIG_DIR"

# Create wrapper script (keeps invocation tidy even when STATUSLINE has spaces)
cat > "$WRAPPER" << EOF
#!/bin/bash
exec python3 "$STATUSLINE"
EOF
chmod +x "$WRAPPER"
echo "Created wrapper: $WRAPPER"

# Update settings.json — idempotent: overwrite statusLine only, preserving rest.
python3 - <<PY
import json, os
from pathlib import Path

settings_path = Path("$SETTINGS")
wrapper       = "$WRAPPER"

if settings_path.exists():
    data = json.loads(settings_path.read_text())
else:
    data = {}

current = data.get("statusLine")
desired = {"type": "command", "command": wrapper, "padding": 0}

if current == desired:
    print(f"Settings already up to date: {settings_path}")
else:
    data["statusLine"] = desired
    settings_path.write_text(json.dumps(data, indent=4))
    print(f"Updated settings: {settings_path}")
PY

echo ""
echo "Done! Restart Claude Code to see the status line."
echo ""
echo "Credentials are auto-detected via CLAUDE_CONFIG_DIR (falls back to ~/.claude)."
