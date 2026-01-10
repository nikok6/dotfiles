#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Get current working directory and git branch
cwd=$(echo "$input" | jq -r '.cwd')
git_branch=$(cd "$cwd" 2>/dev/null && git branch --show-current 2>/dev/null || echo "no-git")

# Extract model name
model_name=$(echo "$input" | jq -r '.model.display_name')

# Get NET lines changed (compare first edit state vs current file state)
transcript_path=$(echo "$input" | jq -r '.transcript_path')
lines_added=0
lines_removed=0

if [ -f "$transcript_path" ]; then
    tmpdir=$(mktemp -d)

    # Single jq pass: extract first originalFile for each unique filePath
    jq -r '
        select(.toolUseResult | type == "object") |
        select(.toolUseResult.filePath and .toolUseResult.originalFile) |
        "\(.toolUseResult.filePath)\n\(.toolUseResult.originalFile)\n<<<END>>>"
    ' "$transcript_path" 2>/dev/null | while true; do
        IFS= read -r filepath || break
        original=""
        while IFS= read -r line; do
            [ "$line" = "<<<END>>>" ] && break
            original+="$line"$'\n'
        done
        safename=$(echo "$filepath" | md5sum | cut -d' ' -f1)
        # Only save first occurrence
        if [ ! -f "$tmpdir/$safename.path" ]; then
            printf '%s' "$original" > "$tmpdir/$safename.original"
            echo "$filepath" > "$tmpdir/$safename.path"
        fi
    done

    # Compare each original to current
    for pathfile in "$tmpdir"/*.path; do
        [ -f "$pathfile" ] || continue
        filepath=$(cat "$pathfile")
        safename=$(basename "$pathfile" .path)

        if [ -f "$filepath" ]; then
            diff_output=$(diff "$tmpdir/$safename.original" "$filepath" 2>/dev/null || true)
            added=$(echo "$diff_output" | grep -c '^>' 2>/dev/null) || added=0
            removed=$(echo "$diff_output" | grep -c '^<' 2>/dev/null) || removed=0
            lines_added=$((lines_added + added))
            lines_removed=$((lines_removed + removed))
        else
            removed=$(wc -l < "$tmpdir/$safename.original" 2>/dev/null) || removed=0
            lines_removed=$((lines_removed + removed))
        fi
    done

    rm -rf "$tmpdir"
fi

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
