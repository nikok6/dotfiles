#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Claude Code dotfiles..."

# Create .claude directory
mkdir -p ~/.claude

# Copy statusline script
cp "$SCRIPT_DIR/claude/statusline-command.sh" ~/.claude/
chmod +x ~/.claude/statusline-command.sh

# Update settings.json with statusLine config
if [ -f ~/.claude/settings.json ]; then
  # Merge statusLine into existing settings
  if command -v jq &> /dev/null; then
    jq '.statusLine = {"type": "command", "command": "~/.claude/statusline-command.sh"}' \
      ~/.claude/settings.json > /tmp/claude-settings.json && mv /tmp/claude-settings.json ~/.claude/settings.json
  else
    echo "Warning: jq not found, cannot merge settings. Please add statusLine config manually."
  fi
else
  # Create new settings.json
  cat > ~/.claude/settings.json << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
EOF
fi

echo "Done! Restart Claude Code to see the statusline."
