#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Claude Code dotfiles..."

# Create .claude directory
mkdir -p ~/.claude

# Copy pre-compiled statusline executable
cp "$SCRIPT_DIR/claude/statusline-command" ~/.claude/
chmod +x ~/.claude/statusline-command
STATUSLINE_CMD="~/.claude/statusline-command"

# Update settings.json with statusLine config
if [ -f ~/.claude/settings.json ]; then
  # Merge statusLine into existing settings
  if command -v jq &> /dev/null; then
    jq --arg cmd "$STATUSLINE_CMD" '.statusLine = {"type": "command", "command": $cmd}' \
      ~/.claude/settings.json > /tmp/claude-settings.json && mv /tmp/claude-settings.json ~/.claude/settings.json
  else
    echo "Warning: jq not found, cannot merge settings. Please add statusLine config manually."
  fi
else
  # Create new settings.json
  cat > ~/.claude/settings.json << EOF
{
  "statusLine": {
    "type": "command",
    "command": "$STATUSLINE_CMD"
  }
}
EOF
fi

echo "Done! Restart Claude Code to see the statusline."
