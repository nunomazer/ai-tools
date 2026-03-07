#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE="$SCRIPT_DIR/statusline.py"
CLAUDE_DIR="$HOME/.claude"
WRAPPER="$CLAUDE_DIR/statusline-wrapper.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "=== Claude Statusline Installer ==="
echo ""

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not found."
    exit 1
fi

# Ensure ~/.claude exists
mkdir -p "$CLAUDE_DIR"

# Create wrapper script (handles paths with spaces)
cat > "$WRAPPER" << EOF
#!/bin/bash
exec python3 "$STATUSLINE"
EOF
chmod +x "$WRAPPER"
echo "Created wrapper: $WRAPPER"

# Update settings.json
if [ -f "$SETTINGS" ]; then
    # Check if statusLine already configured
    if python3 -c "import json; d=json.load(open('$SETTINGS')); assert 'statusLine' not in d" 2>/dev/null; then
        # Add statusLine to existing settings
        python3 -c "
import json
with open('$SETTINGS') as f:
    d = json.load(f)
d['statusLine'] = {'type': 'command', 'command': '$WRAPPER', 'padding': 0}
with open('$SETTINGS', 'w') as f:
    json.dump(d, f, indent=4)
"
        echo "Updated settings: $SETTINGS"
    else
        echo "Settings already has statusLine configured. Skipping."
        echo "To update manually, set command to: $WRAPPER"
    fi
else
    # Create new settings file
    python3 -c "
import json
d = {'statusLine': {'type': 'command', 'command': '$WRAPPER', 'padding': 0}}
with open('$SETTINGS', 'w') as f:
    json.dump(d, f, indent=4)
"
    echo "Created settings: $SETTINGS"
fi

echo ""
echo "Done! Restart Claude Code to see the status line."
echo ""
echo "Note: To enable quota monitoring, update CREDENTIALS_FILE in"
echo "  $STATUSLINE"
echo "to point to your .credentials.json file."
