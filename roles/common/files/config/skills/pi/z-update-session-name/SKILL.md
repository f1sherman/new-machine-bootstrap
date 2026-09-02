---
name: z-update-session-name
description: Update the durable broad name and automatic identity of the current Pi session. User-invoked when the session theme changes.
disable-model-invocation: true
---

# Update Session Name

Update the current Pi session's durable broad name.

- If arguments were supplied after the skill command, use them to identify the requested theme.
- If no arguments were supplied, infer the top-level objective from the current conversation.
- Use the form `[recognizable subject] + [broad outcome]`.
- Preserve the user's central system, initiative, or capability terms when they are clear.
- Put the most distinctive subject terms first. Make the first 31 characters useful for finding the session and include the broad outcome there when practical.
- Name why the session exists. Choose an outcome that stays accurate through related design, implementation, debugging, testing, and review.
- Do not make the current symptom, implementation detail, phase, workflow, or next action the subject.
- Do not use a ticket, repository, or other identifier as the complete name. Keep one only when it is part of a recognizable subject.
- Check the breadth: if the current task disappeared from the transcript, the name must still describe why the session exists.
- For example, use `Pi compaction reliability` instead of `Fix overlay replay`, `Safari URL routing reliability` instead of `Ignore companion panels`, and `Workspace restore reliability` instead of `Debug stale manifests`.
- Prefer a complete name of at most 40 characters. Preserve important meaning up to the hard 80-character limit. Do not create an unclear abbreviation only to fit the discovery target.
- Normalize the result into one concise noun phrase with no quotes or `name:` prefix.
- Call `set_session_name({ name })` exactly once. Pass the phrase as `name`.
- Report the applied name briefly.

Do not edit Pi session files. Do not invoke tmux helpers or rename git branches directly. The `set_session_name` tool is the only mutation interface.
