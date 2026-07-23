# Tmux Subject Feedback Fix

## Problem

Pi’s managed hook currently copies `@window-label` into the Pi session name after successful bash tool calls. A provisional tmux subject is rendered as `~ <subject>`. Changing the Pi session name emits `session_info_changed`, whose handler writes that decorated name back through `tmux-agent-subject set`. Repeating the cycle adds one `~` each time.

The raw task identity and its rendered tmux label have become a feedback loop:

1. raw subject `Investigate reviewer failures`
2. rendered window label `~ Investigate reviewer failures`
3. Pi session name becomes `~ Investigate reviewer failures`
4. session-name handler stores that value as the raw subject
5. next render becomes `~ ~ Investigate reviewer failures`

## Design

Keep canonical task identity separate from display decoration. `syncSessionNameFromTmux` will inspect canonical tmux task state before deriving a Pi session name from `@window-label`.

When the pane has a valid provisional agent task, tmux-to-Pi session-name synchronization will do nothing. Session-goal naming remains authoritative for these sessions. Branch-backed task naming continues through the existing canonical branch path, and panes without canonical task state retain the existing window-label fallback.

The shell helpers will not strip or reject leading `~` or `✓`. Those characters can be valid literal subject content, and fixing the producer-consumer boundary avoids encoding display syntax in the subject API.

## Data Flow

- User prompt or explicit command establishes a raw provisional subject.
- `tmux-agent-state` renders the `~` marker for tmux only.
- Successful bash results call `syncSessionNameFromTmux`.
- Canonical provisional agent state causes that fallback sync to return without changing the Pi session name.
- No `session_info_changed` event is generated from the decorated label, so no decorated value is written back as a subject.

## Testing

Extend `tests/pi-managed-hooks.sh` with a regression covering canonical provisional state. Simulate repeated successful bash results and assert:

- no decorated `@window-label` value is passed to `pi.setSessionName`;
- no additional `tmux-agent-subject set` call is triggered through session-name feedback;
- existing fallback naming still works when canonical task state is absent;
- existing branch/session-goal behavior remains unchanged.

Run the managed-hooks test suite and relevant tmux task-state tests before provisioning.

## Scope

Only the Pi managed-hook feedback boundary changes. No tmux rendering, shell subject sanitization, session-goal generation, or branch naming behavior changes.
