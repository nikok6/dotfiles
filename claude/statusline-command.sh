#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Get current working directory from JSON input
cwd=$(echo "$input" | jq -r '.cwd')

# Get git branch
git_branch=$(cd "$cwd" 2>/dev/null && git branch --show-current 2>/dev/null || echo "no-git")

# Extract model name
model_name=$(echo "$input" | jq -r '.model.display_name')

# Get lines changed
lines_added=$(echo "$input" | jq '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq '.cost.total_lines_removed // 0')
lines_changed=$((lines_added + lines_removed))

# Calculate token usage from current context (not cumulative)
usage=$(echo "$input" | jq '.context_window.current_usage')
if [ "$usage" != "null" ]; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    size=$(echo "$input" | jq '.context_window.context_window_size')
    pct=$((current * 100 / size))

    # Format with k suffix
    current_k=$((current / 1000))
    size_k=$((size / 1000))

    # Build progress bar (5 segments)
    filled=$((pct / 20))
    empty=$((5 - filled))
    bar=""
    for ((i=0; i<filled; i++)); do bar+="▰"; done
    for ((i=0; i<empty; i++)); do bar+="▱"; done

    token_info="\033[38;5;216m${bar} ${current_k}k/${size_k}k tokens\033[0m"
fi

# Output: branch · model · context
printf "\033[38;5;111m%s\033[0m | \033[38;5;151m+%s\033[0m \033[38;5;211m-%s\033[0m | \033[38;5;183m%s\033[0m | %b" "$git_branch" "$lines_added" "$lines_removed" "$model_name" "$token_info"
