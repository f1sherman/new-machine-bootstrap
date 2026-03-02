#!/bin/bash
# PreToolUse/UserPromptSubmit hook: clear the "waiting" indicator
# Re-sends the normal title to the tmux client's terminal.

[ -z "$TMUX" ] && exit 0

title=$(tmux display-message -p '#S')
client_tty=$(tmux display-message -p '#{client_tty}' 2>/dev/null)
[ -n "$client_tty" ] && printf '\033]2;%s\033\\' "$title" > "$client_tty"
exit 0
