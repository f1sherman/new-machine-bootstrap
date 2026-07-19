# Pi Subagent Tmux Subject Design

## Goal

Set a concise provisional tmux task subject before Pi's main agent turn without adding subject-selection guidance or tool calls to the main agent's context.

## Scope

This changes Pi only. Claude and Codex keep their existing prompt reminders. Existing branch promotion and completed-task behavior remain unchanged.

## Design

When `managed-hooks.ts` sees an empty or completed tmux task state in `before_agent_start`, it starts a sessionless Pi child process and waits for it before allowing the main agent turn to begin.

The child receives:

- a narrow system prompt asking for one concise noun phrase
- the current user prompt
- no repository context, skills, or tools
- the explicit lightweight model `openai-codex/gpt-5.3-codex-spark`

The child returns only the proposed subject. The hook trims surrounding whitespace, accepts only a single non-empty line of at most 512 characters (matching `tmux-agent-state`), and rejects malformed output. The hook then runs:

```text
tmux-agent-subject set <validated subject>
```

The child never receives shell access. The parent hook owns the state mutation, avoiding recursive managed-hook execution and preventing prompt content from turning into arbitrary commands.

No successful subject-selection message is injected into the main conversation. The main agent therefore begins with the label already set and spends no context or tool call on labeling.

## Failure Handling

Child startup, model, timeout, or validation failures must not block the user's task. On failure, `managed-hooks.ts` emits the current `tmux-agent-subject set` reminder so the main agent can recover using the existing behavior.

The child process has a 15-second timeout and is terminated when the hook's operation is cancelled or expires. Diagnostic warnings identify child failures without including the full user prompt.

## Components

### Managed hook

Add helpers to:

1. invoke the sessionless Pi child with isolated prompt and tool configuration
2. parse and validate its final text response
3. apply the subject through `tmux-agent-subject`
4. return the existing reminder only when automatic labeling fails

### Tests

Extend `tests/pi-managed-hooks.sh` to verify:

- empty and completed states invoke the child and apply its valid subject
- provisional and active states do not invoke the child
- successful automatic labeling injects no reminder
- malformed, empty, timed-out, and failed child results preserve the existing reminder
- user prompt text is passed as data and never interpolated into a shell command

## Non-goals

- Automatic subject generation for Claude or Codex
- Changing branch-derived or completed tmux labels
- Persisting child conversations or exposing child output to the main context
- Giving the label child repository tools or shell access
