---
name: z-update-session-name
description: Update the durable broad name and automatic identity of the current Pi session. User-invoked when the session theme changes.
disable-model-invocation: true
---

# Update Session Name

Update the current Pi session's durable broad name.

- If arguments were supplied after the skill command, treat them as the requested theme.
- If no arguments were supplied, infer the broad theme from the current conversation.
- Normalize the result into one concise noun phrase targeting 40 characters or fewer, with no quotes or `name:` prefix.
- Call `set_session_name({ name })` exactly once. Pass the phrase as `name`.
- Report the applied name briefly.

Do not edit Pi session files. Do not invoke tmux helpers or rename git branches directly. The `set_session_name` tool is the only mutation interface.
