#!/bin/bash

# Read the JSON input from stdin
input=$(cat)

# Extract information from the JSON
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // "'"$(pwd)"'"')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // "'"$(pwd)"'"')

# Calculate context window percentage
usage=$(echo "$input" | jq '.context_window.current_usage')
if [ "$usage" != "null" ] && [ "$usage" != "" ]; then
    current=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    size=$(echo "$input" | jq '.context_window.context_window_size')
    if [ "$current" != "null" ] && [ "$current" != "" ] && [ "$size" != "null" ] && [ "$size" != "" ] && [ "$size" -gt 0 ]; then
        pct=$((current * 100 / size))
        context_info=" | ${pct}% ctx"
    else
        context_info=""
    fi
else
    context_info=""
fi

# Truncate directory if too long (similar to your zsh prompt)
# Show last 4 directories, or last 2 with ... if longer than 5
dir_display=$(echo "$current_dir" | sed 's|'"$HOME"'|~|')
if [ $(echo "$dir_display" | tr '/' '\n' | wc -l) -gt 5 ]; then
    dir_display=$(echo "$dir_display" | sed -E 's|([^/]/[^/]/).*/([^/]/[^/]/[^/]/[^/])$|\1...\2|')
elif [ $(echo "$dir_display" | tr '/' '\n' | wc -l) -gt 4 ]; then
    dir_display=$(echo "$dir_display" | sed -E 's|^.*/([^/]/[^/]/[^/]/[^/])$|\1|')
fi

# Git information
git_info=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    # Get git branch or short commit hash
    git_ref=$(git symbolic-ref HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$git_ref" ]; then
        branch_name=$(echo "$git_ref" | sed 's|refs/heads/||')

        # Check if working directory is dirty
        if [ -n "$(git status --porcelain 2>/dev/null | tail -n1)" ]; then
            git_status=" X"
        else
            git_status=" OK"
        fi

        git_info=" ${branch_name}${git_status}"
    fi
fi

# Build the status line
printf "\033[1m%s%s\033[0m | %s%s\n" "$dir_display" "$git_info" "$model_name" "$context_info"
