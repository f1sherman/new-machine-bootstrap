#!/bin/bash
# Stop hook: signal that Claude is waiting for user input
# Sends an OSC title escape directly to the tmux client's terminal
# so it propagates through nested tmux/SSH to the Ghostty tab title.

[ -z "$TMUX" ] && exit 0

title=$(tmux display-message -p '#S')
client_tty=$(tmux display-message -p '#{client_tty}' 2>/dev/null)
[ -n "$client_tty" ] && printf '\033]2;⏳ %s\033\\' "$title" > "$client_tty"
exit 0
