# Luna Small Models Design

## Goal

Use GPT-5.6 Luna for lightweight managed Pi child tasks. Preserve the current provider selection based on available authentication.

## Scope

Change the active managed child-model identifiers:

- `openai-codex/gpt-5.4-mini` becomes `openai-codex/gpt-5.6-luna`.
- `openai/gpt-4.1-mini` becomes `openai/gpt-5.6-luna`.

Keep `openai-codex` as the preferred provider when usable Codex OAuth credentials exist. Keep `openai` as the fallback provider. Do not change the authentication inspection or selection logic.

Update current automated test expectations. Do not edit historical specifications, plans, generated artifacts, other worktrees, or unrelated Claude agent model settings.

## Implementation

Update the two managed model constants in `roles/common/files/pi/extensions/managed-hooks.ts`. Update matching assertions and expected child arguments in `tests/pi-managed-hooks.sh`.

No new fallback, compatibility detection, configuration option, or shared abstraction is required.

## Failure Behavior

Existing authentication inspection failures continue to select the `openai` provider. Existing child-process failure handling remains unchanged.

## Verification

Run:

1. `bash tests/pi-managed-hooks.sh`
2. The repository test suite.
3. `bin/provision`
4. `bin/provision --check`

Confirm that focused tests observe Luna with the correct provider for each authentication path and that provisioning is idempotent.
