#!/bin/bash

# Install chezmoi and apply dotfiles
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply nikok6

# Install claude-statusline
curl -fsSL https://raw.githubusercontent.com/nikok6/claude-statusline/main/install.sh | bash
