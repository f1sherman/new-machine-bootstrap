# Pi Managed Child Model Selection Design

## Goal

Choose the provider and model for both managed Pi child tasks—the tmux subject generator and session goal evaluator—based on whether this machine has Pi Codex subscription authentication.

## Model Selection

Use one shared resolver with this precedence:

1. A non-empty `PI_MANAGED_CHILD_MODEL` environment variable.
2. `openai-codex/gpt-5.4-mini` when `~/.pi/agent/auth.json` contains a usable `openai-codex` OAuth credential.
3. `openai/gpt-4.1-mini` otherwise.

A usable Codex credential is an object whose `type` is `oauth` and whose `access` and `refresh` fields are non-empty strings. An expired access token remains usable when a refresh token is present because Pi refreshes OAuth credentials. Missing, malformed, unreadable, or incomplete auth data is treated as no Codex authentication. The extension must not log credentials or auth-file contents.

## Cache Behavior

The extension keeps an in-process cache containing the auth-file signature and selected model. Each resolution performs a filesystem metadata check only. It reparses the auth file when its signature changes, allowing Pi `/login` and `/logout` changes to take effect without restarting Pi.

The signature consists of the file device, inode, size, modification time, and change time, detecting both in-place rewrites and atomic replacement. Missing-file state is cacheable. The environment override is checked before the auth cache so setting or changing it affects subsequent child launches immediately.

## Integration

Replace the fixed child-model constant with the shared resolver. Both `setSubjectFromSubagent` and `evaluateSessionGoal` resolve the model immediately before constructing their `pi` command and pass the result to `--model`.

All existing prompts, isolation flags, thinking settings, timeouts, output validation, queueing, and failure handling remain unchanged.

## Failure Handling

Auth inspection failures select `openai/gpt-4.1-mini`; they do not prevent the child from running. Existing child-process failures continue through the current warning and retry behavior. No automatic retry across providers is added.

## Verification

Extend `tests/pi-managed-hooks.sh` to verify:

- Codex OAuth credentials select `openai-codex/gpt-5.4-mini`.
- Missing, malformed, unreadable, or non-OAuth Codex credentials select `openai/gpt-4.1-mini`.
- `PI_MANAGED_CHILD_MODEL` overrides automatic selection.
- Repeated calls reuse cached parsed auth state.
- Rewriting or replacing the auth file invalidates the cache.
- Both managed child call sites use the selected model.

Run the focused managed-hooks tests, repository contract checks, `git diff --check`, provisioning, and real isolated child invocations for the authenticated provider paths available on the current machine.

## Non-goals

- Synchronizing Codex credentials between machines.
- Validating credentials with a network request before every child launch.
- Falling back to another provider after a child request fails.
- Changing model selection for ordinary Pi sessions or pi-subagents.
