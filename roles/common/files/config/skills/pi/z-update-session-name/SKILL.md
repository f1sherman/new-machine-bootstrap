---
name: z-update-session-name
description: Update the durable broad name and automatic identity of the current Pi session. User-invoked when the session theme changes.
disable-model-invocation: true
---

# Update Session Name

Update the current Pi session's durable broad name.

- If arguments were supplied after the skill command, use them to identify the requested theme.
- If no arguments were supplied, infer the broad theme from the current conversation.
- Name the problem to solve or the intended outcome in terms that will still be recognizable later.
- Infer that meaning when the request emphasizes a ticket, repository, workflow, or phase.
- Do not use an identifier or an activity such as design, implementation, debugging, or review as the main subject.
- Normalize the result into one concise noun phrase targeting 40 characters or fewer, with no quotes or `name:` prefix.
- Call `set_session_name({ name })` exactly once. Pass the phrase as `name`.
- Report the applied name briefly.

Do not edit Pi session files. Do not invoke tmux helpers or rename git branches directly. The `set_session_name` tool is the only mutation interface.
