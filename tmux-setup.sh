
#!/usr/bin/env bash

# we can put this script to a project home, and modify the project name and directory
# Compatible with both bash and zsh (source or direct execution)
if [ -n "$BASH_SOURCE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "$ZSH_VERSION" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

SESSIONS=("tt-to-dsl" "flydsl" "triton")
WINDOWS=("claude" "yaz" "git" "diff" "vim" "others")

# Session -> directory mapping
declare -A SESSION_DIRS
SESSION_DIRS[llvm]="$SCRIPT_DIR/llvm"
SESSION_DIRS[triton]="$SCRIPT_DIR/triton"
SESSION_DIRS[cutedsl]="$SCRIPT_DIR/cutedsl"

# Kill existing sessions if they exist
for sess in "${SESSIONS[@]}"; do
    tmux kill-session -t "$sess" 2>/dev/null
done

# Get first window name (zsh arrays are 1-indexed, bash are 0-indexed)
if [ -n "$ZSH_VERSION" ]; then
    FIRST_WIN="${WINDOWS[1]}"
    REST_WINS=("${WINDOWS[@]:1}")
    FIRST_SESS="${SESSIONS[1]}"
else
    FIRST_WIN="${WINDOWS[0]}"
    REST_WINS=("${WINDOWS[@]:1}")
    FIRST_SESS="${SESSIONS[0]}"
fi

for sess in "${SESSIONS[@]}"; do
    dir="${SESSION_DIRS[$sess]}"

    # Create session with first window
    tmux new-session -d -s "$sess" -n "$FIRST_WIN" -c "$dir"

    # Create remaining windows
    for win in "${REST_WINS[@]}"; do
        tmux new-window -t "$sess" -n "$win" -c "$dir"
    done

    # Select first window
    tmux select-window -t "$sess:$FIRST_WIN"
done

# Attach to the first session
tmux attach-session -t "$FIRST_SESS"

