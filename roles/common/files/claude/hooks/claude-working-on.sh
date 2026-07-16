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

# Keep the remote edge marker alive while Claude works so C-h/j/k/l can
# still fall back to outer-tmux panes; empty on local sessions. $HOME path
# first: hooks may run without ~/.local/bin on PATH.
suffix=""
if [ -x "$HOME/.local/bin/tmux-edge-suffix" ]; then
  suffix="$("$HOME/.local/bin/tmux-edge-suffix" "$session_id" 2>/dev/null || true)"
elif command -v tmux-edge-suffix >/dev/null 2>&1; then
  suffix="$(tmux-edge-suffix "$session_id" 2>/dev/null || true)"
fi

while IFS= read -r tty; do
  [ -n "$tty" ] && printf '\033]2;⏳ %s%s\033\\' "$title" "$suffix" > "$tty"
done < <(tmux list-clients -t "$session_id" -F '#{client_tty}' 2>/dev/null)
exit 0
