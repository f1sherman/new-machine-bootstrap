#!/bin/bash
# UserPromptSubmit hook: clear the "waiting" indicator when user submits a prompt

[ -n "$TMUX" ] && tmux set -gu @claude-waiting 2>/dev/null
exit 0
