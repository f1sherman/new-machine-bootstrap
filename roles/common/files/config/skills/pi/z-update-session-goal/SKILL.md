---
name: z-update-session-goal
description: Update the durable broad goal and automatic identity of the current Pi session. User-invoked when the session theme changes.
disable-model-invocation: true
---

# Update Session Goal

Update the current Pi session's durable broad goal.

- If arguments were supplied after the skill command, treat them as the requested theme.
- If no arguments were supplied, infer the broad theme from the current conversation.
- Normalize the result into one concise noun phrase targeting 40 characters or fewer, with no quotes or `goal:` prefix.
- Call `set_session_goal` exactly once with that phrase.
- Report the applied goal briefly.

Do not edit Pi session files. Do not invoke tmux helpers or rename git branches directly. The `set_session_goal` tool is the only mutation interface.
