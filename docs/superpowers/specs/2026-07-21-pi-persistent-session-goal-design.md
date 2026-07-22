# Persistent Pi Session Goal Design

## Problem

Pi currently generates a lightweight task subject only when tmux task state is missing or completed. A feature branch then replaces that subject as the managed Pi session name. This makes branch identity durable, but Pi no longer exposes the broader goal or theme of a session as the conversation evolves.

The session goal and the branch name answer different questions:

- the goal describes what the session is trying to accomplish;
- the branch identifies where repository changes are being made.

Pi should keep evaluating and displaying the goal without changing the existing branch-oriented tmux behavior.

## Goals

- Always show the current session goal in Pi's status bar as `goal: <subject>`.
- Reconsider the goal after every expanded user prompt without delaying the main agent.
- Keep the subject broad and stable across small follow-ups, updating it only when the session goal meaningfully changes.
- Persist the latest valid subject in the Pi session so resume, reload, fork, and tree navigation restore the correct goal.
- Continue using the subject as the managed Pi session name before a feature branch exists.
- Continue using the branch name as the managed Pi session name after a feature branch exists.
- Preserve manual `/name` values.
- Surface repeated evaluator failures without producing notification noise.

## Non-goals

- Do not change tmux pane, window, branch, worktree, or remote-title label behavior.
- Do not replace Pi's built-in footer.
- Do not send session-goal state into the main model's conversation context.
- Do not update Claude or Codex subject behavior.
- Do not infer old goal state from legacy session names or tmux labels.

## User-visible Behavior

A new Pi session initially shows:

```text
goal: determining…
```

After the first successful evaluation it shows a concise theme, for example:

```text
goal: persistent Pi session goals
```

The status remains visible through Pi's standard extension-status area. Follow-up prompts such as `yes`, `continue`, or requests for tests retain the existing theme. A prompt that redirects the session to a different objective changes the displayed goal asynchronously.

Before a feature branch exists, the automatically managed Pi session name follows the goal subject. After branch creation, the automatically managed Pi session name follows the branch as it does today, while the status bar continues showing the evolving goal. A manual `/name` remains authoritative for the session name but does not suppress goal evaluation or display.

## Architecture

Extend `roles/common/files/pi/extensions/managed-hooks.ts` with a session-goal subsystem independent of tmux task identity.

The subsystem has four responsibilities:

1. restore durable goal state for the active session branch;
2. render the current goal through `ctx.ui.setStatus("session-goal", ...)`;
3. schedule nonblocking lightweight evaluations;
4. apply valid results to durable state and, when allowed, the managed Pi session name.

The existing tmux synchronization remains responsible for branch-driven session naming. Goal evaluation reads branch activity only to decide whether it may update the managed Pi session name; it does not write tmux task state.

## Durable State

Store each changed goal with `pi.appendEntry()` under a dedicated custom entry type. Custom entries are durable but excluded from model context.

On `session_start`, scan `ctx.sessionManager.getBranch()` for the latest valid goal entry. This respects the active conversation branch during resume, fork, clone, and tree navigation. Restore that subject immediately to the status bar. If none exists, render `goal: determining…` until evaluation succeeds.

Only append when the normalized subject differs from the current subject. `KEEP` evaluations and repeated equivalent subjects create no entries.

Session replacement and shutdown invalidate the extension instance's pending evaluator work. A result may apply only if its captured session file and extension generation still match the active session.

## Evaluation Trigger and Prompt

Use `before_agent_start`, where Pi exposes the expanded user prompt, rather than the raw `input` event. This gives the evaluator the effective task text for skills and prompt templates.

Every user prompt schedules evaluation, but the hook does not await it. The main agent starts normally while the lightweight child runs in the background.

Invoke an isolated Pi child using `openai-codex/gpt-5.4-mini`, thinking off, with tools, extensions, skills, prompt templates, themes, context files, session persistence, and approval disabled. Give it only:

- the current goal, if any;
- the newest expanded user prompt;
- instructions to return `KEEP` when the broad goal has not meaningfully changed, otherwise one concise noun phrase.

The evaluator should treat acknowledgements, implementation details, verification requests, and minor scope additions as part of the existing theme. It should update only for a genuine goal shift. The output must contain exactly one line.

## Concurrency and Coalescing

Allow only one evaluator child at a time per extension instance.

If another prompt arrives while evaluation is running, retain one pending request containing the newest expanded prompt. When the running child finishes:

- discard its result if a newer request is pending, preventing transient stale updates;
- immediately evaluate the pending request against the still-current subject;
- continue until no request remains.

Each request carries a monotonically increasing generation identifier plus the current session file identity. Late output from an earlier prompt or replaced session cannot mutate current state.

This coalescing bounds process count and cost during rapid steering while ensuring the final visible goal reflects the newest request.

## Validation and Application

Accept either the exact sentinel `KEEP` or a normalized subject. A subject must:

- be non-empty;
- contain no newline, carriage return, or control characters;
- collapse repeated whitespace;
- be no longer than 80 characters;
- not include a prefix such as `goal:`, quotes, or explanatory prose.

A valid `KEEP` is a successful evaluation and leaves state unchanged. A valid new subject:

1. becomes the in-memory current goal;
2. is appended as a custom session entry;
3. updates the status to `goal: <subject>`;
4. updates the Pi session name only if no active branch task exists and the current name is empty or still managed by this extension.

Immediately before changing the session name, re-read canonical tmux task status. An active branch wins any race with asynchronous goal generation. Outside tmux, goal persistence and display still work; branch-driven naming retains the existing best-effort limitations.

The existing managed-name marker and in-memory tracking continue distinguishing automatic names from manual `/name` values. Goal status updates never depend on permission to rename the session.

## Failure Handling

Timeouts, nonzero child exits, cancellation, invalid output, and persistence/application errors preserve the last valid goal. Diagnostics must contain safe failure metadata and must not echo user prompts or raw child output.

Track consecutive evaluator failures:

- failures 1 and 2: diagnostics only;
- failure 3: show one warning notification: `Session goal updates are failing; keeping the previous goal.`;
- subsequent warnings: one after every 10 additional consecutive failures, at failures 13, 23, and so on;
- any successful `KEEP` or valid-subject evaluation resets the counter.

When no valid goal exists, failures leave `goal: determining…` visible and the next user prompt retries evaluation.

A stale result discarded because a newer request exists is not a failure. Session shutdown cancellation is also not reported as a failure.

## Lifecycle

### Session start and resume

Reset transient concurrency state, advance the extension generation, restore the latest goal entry from the active branch, and render either that goal or the determining placeholder.

### Reload, new session, resume, and fork

`session_shutdown` aborts the running child and clears pending work. The replacement extension instance restores only the destination session's state.

### Branch creation

The existing successful-bash-result synchronization reads tmux `@window-label` and changes an automatically managed Pi session name to the branch. Goal status and durable subject remain independent.

### Manual naming

A user-supplied `/name` prevents later automatic goal or branch naming under the current managed-name rules. The status bar still tracks the session goal.

### Noninteractive modes

Evaluation and persistence may run where appropriate, while UI calls remain harmless no-ops outside TUI/RPC modes. The feature must not require a TUI to preserve session state.

## Testing

Extend `tests/pi-managed-hooks.sh` with deterministic child and lifecycle stubs covering:

- registration of required Pi events;
- `goal: determining…` for a session without durable state;
- immediate restoration of the latest active-branch goal entry;
- `before_agent_start` returning without awaiting child completion;
- isolated GPT-5.4 mini child arguments and prompt framing;
- `KEEP` preserving state without appending an entry;
- changed output appending one entry and updating status;
- whitespace normalization and invalid, multiline, prefixed, quoted, control-character, and oversized output rejection;
- one running child with newest-prompt coalescing;
- stale prompt and stale session result rejection;
- failure warnings at 3 and 13 consecutive failures;
- failure-counter reset after `KEEP` and changed-subject success;
- shutdown cancellation producing no warning;
- subject-driven managed naming before a branch;
- branch-driven managed naming after branch creation, including the asynchronous race check;
- manual `/name` preservation while goal status continues updating;
- operation outside tmux and in non-TUI modes.

Run the focused managed-hook test and the repository's broader relevant shell test suite. Provision with `bin/provision` when the environment permits, then confirm in an interactive Pi session that the status appears immediately, updates asynchronously, survives resume, and remains a goal after branch creation.

## Cost and Performance

The evaluator receives only the previous subject, one expanded prompt, and a short system instruction. At GPT-5.4 mini standard pricing, typical token cost is expected to remain roughly $0.0001–$0.0003 per user prompt. Coalescing bounds concurrent process use.

The main interaction path does not await evaluator process startup or inference. Status can briefly show the previous goal while evaluation runs, then rerenders when the result arrives.
