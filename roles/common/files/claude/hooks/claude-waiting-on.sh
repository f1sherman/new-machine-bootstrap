#!/bin/bash
# Stop hook: signal that Claude is waiting for user input
# Sets a tmux user option that gets picked up by set-titles-string,
# propagating through nested tmux/SSH to the Ghostty tab title.

[ -n "$TMUX" ] && tmux set -g @claude-waiting 1 2>/dev/null
exit 0
