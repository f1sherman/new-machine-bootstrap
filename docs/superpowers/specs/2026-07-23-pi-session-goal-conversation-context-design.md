# Pi Session Goal Conversation Context Design

## Problem

The managed Pi extension evaluates every user prompt against only the current session goal and the newest prompt. This loses conversational context for short replies to an agent question. For example, when an agent presents choices and the user replies `C`, the evaluator can interpret `C` as a new broad goal, persist it, and rename the managed Pi session to `C`.

The automatic naming should still recognize genuine goal changes without relying on a growing conversation transcript or an expanding list of special-case replies.

## Design

Give the existing session-goal evaluator one bounded piece of conversation context: the most recent assistant text on the active session branch.

Before queueing an evaluation, the extension will scan the active branch from newest to oldest for the latest assistant message. It will combine that message's text blocks, normalize surrounding whitespace, and retain only the final 800 characters. The tail is preferred because questions, choices, and approval requests normally appear at the end of an assistant response.

Each evaluator request will contain:

1. The current broad goal, or `(none)`.
2. The bounded preceding assistant context, or `(none)`.
3. The newest user prompt.

The evaluator system prompt will explicitly distinguish conversational replies from goal changes. A reply that answers, selects from, approves, or continues the preceding assistant message should return `KEEP` when it remains within the current broad goal. It should produce a new noun phrase only when the combined context demonstrates a genuine change in the session's broad goal.

The model, timeout, asynchronous queue, prompt coalescing, lifecycle guards, persistence, output validation, and managed-name ownership rules remain unchanged.

## Cost Bound

The extension will include at most 800 characters of preceding assistant text. It will not send the full session, tool results, reasoning blocks, images, or older messages. The evaluator already runs once for each expanded user prompt, so this changes only bounded input size and does not add model calls.

A fixed bound is preferred over classifying prompts as terse or maintaining a list of replies such as `yes`, `C`, or `continue`. This keeps behavior predictable and covers both short and detailed follow-ups without a growing heuristic surface.

## Data Flow

1. Pi fires `before_agent_start` with the newest expanded user prompt.
2. The extension reads the active branch from `ctx.sessionManager.getBranch()`.
3. It extracts and bounds the latest preceding assistant text.
4. It queues the current goal, assistant context, and user prompt as one evaluator request.
5. The isolated mini-model returns `KEEP` or a validated noun phrase.
6. Existing logic either preserves the goal or persists and publishes the changed goal.

## Failure Handling

If no assistant message exists, the evaluator receives `(none)` and retains current behavior for initial prompts.

Unsupported or empty assistant content becomes `(none)`. Extraction errors must not block the user turn; the extension should fall back to no assistant context.

Existing handling remains authoritative for child-process failures, timeouts, malformed output, stale requests, session changes, branch naming races, and manually assigned session names.

## Testing

Extend `tests/pi-managed-hooks.sh` to verify:

- The evaluator receives the final 800 characters of the latest assistant text, not the full response.
- Multiple assistant text blocks are combined while thinking and tool-call blocks are excluded.
- A `C` reply after an A/B/C question is framed with that question and a `KEEP` result preserves the existing goal and managed session name.
- An approval reply such as `yes` can preserve the existing goal.
- An explicit redirect still applies a new goal and managed session name.
- A session without prior assistant text uses `(none)`.
- Existing coalescing, lifecycle, validation, and naming tests continue to pass.

## Scope

This change affects only Pi's managed session-goal evaluator in `roles/common/files/pi/extensions/managed-hooks.ts` and its contract tests. It does not alter tmux label formatting, branch-derived names, manual session naming, other agent integrations, or evaluator call frequency.
