#!/bin/bash
# Show icon in terminal tab title when Claude is actively working.
# Sends an OSC title escape to the terminal(s) attached to THIS session
# so it propagates through nested tmux/SSH to the Ghostty tab title.
#
# Target the clients attached to this hook's own session, not a bare
# `#{client_tty}`: with multiple clients attached, that resolves to the
# globally most-recent client, stamping this title onto an unrelated tab.

[ -z "$TMUX" ] && exit 0

title=$(tmux display-message -p '#S')
session_id=$(tmux display-message -p '#{session_id}')
[ -n "$session_id" ] || exit 0

while IFS= read -r tty; do
  [ -n "$tty" ] && printf '\033]2;⏳ %s\033\\' "$title" > "$tty"
done < <(tmux list-clients -t "$session_id" -F '#{client_tty}' 2>/dev/null)
exit 0
