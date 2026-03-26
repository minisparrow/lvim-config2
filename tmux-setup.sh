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

declare -A SESSION_DIRS

# Session -> directory mapping
SESSION_DIRS["lv"]="/Users/jun/.config/lvim/lvim-config2/"
SESSION_DIRS["projs"]="/Users/jun/projs/"
SESSION_DIRS["obs"]="/Users/jun/doc/icloud-obs-git"
SESSIONS=("${!SESSION_DIRS[@]}")
WINDOWS=("claude" "yaz" "git" "diff" "vim" "others")

# Kill existing sessions if they exist
# for sess in "${SESSIONS[@]}"; do
#     tmux kill-session -t "$sess" 2>/dev/null
# done

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

# Argument parsing
ATTACH_SESSION=""
LIST_ONLY=0

while getopts "a:l" opt; do
    case "$opt" in
        a) ATTACH_SESSION="$OPTARG";;
        l) LIST_ONLY=1;;
        ?) echo "Usage: $0 [-a <session_name>] [-l]" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))

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

if [ "$LIST_ONLY" -eq 1 ]; then
    echo "Tmux sessions created. Use 'tmux attach -t <session_name>' to connect."
    tmux list-sessions
elif [ -n "$ATTACH_SESSION" ]; then
    if tmux has-session -t "$ATTACH_SESSION" 2>/dev/null; then
        tmux attach-session -t "$ATTACH_SESSION"
    else
        echo "Error: Session '$ATTACH_SESSION' not found. Available sessions:"
        tmux list-sessions
        exit 1
    fi
else
    tmux attach-session -t "$FIRST_SESS"
fi
