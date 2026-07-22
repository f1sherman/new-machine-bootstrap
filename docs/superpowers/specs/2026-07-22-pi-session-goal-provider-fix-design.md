# Pi Session Goal Provider Fix

Date: 2026-07-22
Status: Approved

## Problem

The managed-hooks extension launches subject and session-goal children with `openai-codex/gpt-5.4-mini`. Provisioned environments use `OPENAI_API_KEY` and expose the model through the `openai` provider, but do not necessarily have separate `openai-codex` OAuth credentials. Each child therefore exits with code 1; after three session-goal failures, Pi warns that goal updates are failing.

## Design

Change the shared managed child model identifier to `openai/gpt-5.4-mini`. Keep the model family, child prompts, isolation flags, timeout, output validation, and failure handling unchanged. Both tmux-subject and session-goal children intentionally share this configured provider because both use the same constant and credential environment.

Do not add provider fallback logic or require an additional Codex login. The provisioned `openai` provider is the existing supported credential path.

## Testing

Extend the managed-hooks contract test to assert the `openai/gpt-5.4-mini` child model and reject the obsolete `openai-codex` identifier. Run the extension test suite, provision from the feature worktree, and execute an isolated child command with the deployed model to confirm an exit-zero one-line response.
