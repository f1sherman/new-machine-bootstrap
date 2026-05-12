# Auto-trust provisioned Codex hooks

**Status:** Draft
**Date:** 2026-05-12

## Goal

Provisioned Codex hooks should be trusted automatically after `bin/provision`.
The user should not need to open Codex and approve each bootstrap-managed hook
after the repo writes `~/.codex/hooks.json`.

After this change:

- every Codex hook entry managed by `new-machine-bootstrap` is trusted
- unrelated user hooks remain untouched
- hook trust is refreshed idempotently when the managed hook content changes
- `~/.codex/hooks.json` and `~/.codex/config.toml` stay `0600`

## Non-goals

- No repo-local `.codex/hooks.json` files.
- No changes to hook behavior or hook helper scripts.
- No blanket trust for every hook in `~/.codex/hooks.json`.
- No migration to plugin-managed or MDM-managed hooks.
- No direct edits outside this repo during implementation; provisioning remains
  the mechanism that changes files under `~`.

## Current State

`roles/common/tasks/main.yml` already does the Codex hook provisioning:

1. Enables hooks with `[features] hooks = true` in `~/.codex/config.toml`.
2. Merges these user-level hook entries into `~/.codex/hooks.json`:
   - `codex-block-worktree-commands`
   - `codex-block-git-push-main`
   - `codex-bind-tmux-pane`
   - `codex-block-main-branch-edits`
   - `agent-current-spec-hook`
   - `codex-remind-repo-start-on-dev-prompt`
3. Enforces `0600` on both Codex config files.

Codex CLI 0.130.0 reports hook metadata through `hooks/list`. For user-level
hooks, trust is not represented inside `hooks.json`; it is stored in
`~/.codex/config.toml` under `[hooks.state]` as:

```toml
[hooks.state."<hook-key>"]
trusted_hash = "<current-hash>"
```

The hook key includes the source file, event name, matcher-group index, and
handler index, for example:

```text
/Users/brian/.codex/hooks.json:pre_tool_use:0:0
```

`hooks/list` reports each hook's `key`, `currentHash`, `source`, `sourcePath`,
`matcher`, `command`, `timeoutSec`, and `trustStatus`. A hook is trusted when
the configured `trusted_hash` equals the reported `currentHash`.

## Assumptions

- `@openai/codex` is installed before the hook trust task runs. This is already
  true in the common role because Codex installation precedes config and hook
  provisioning.
- `codex app-server --listen stdio://` can be used noninteractively to call
  `hooks/list`; local verification showed this works without network or auth.
- The authoritative way to avoid hash algorithm drift is to ask Codex for
  `currentHash` instead of reimplementing the hash algorithm in this repo.
- Only hooks that exactly match this repo's managed event, matcher, command,
  and timeout should be auto-trusted.
- The current user-level hook location stays `~/.codex/hooks.json`.

## Recommended Approach

Add a final "trust managed Codex hooks" provisioning step after all managed
hook merge tasks and before the final file-mode enforcement.

The step should:

1. Query Codex `hooks/list` for the current `~/.codex/hooks.json` metadata.
2. Select only the hooks matching the managed hook manifest.
3. Write `[hooks.state."<key>"].trusted_hash = "<currentHash>"` into
   `~/.codex/config.toml`.
4. Preserve unrelated config content and unrelated hook state.
5. Remove stale trust entries for the same managed command when an entry moved
   to a different key.
6. Print `changed` only when `config.toml` actually changed.

The managed hook manifest should be explicit and live next to the provisioning
logic, so implementation does not accidentally trust arbitrary hooks:

| Event | Matcher | Command | Timeout |
| --- | --- | --- | --- |
| `preToolUse` | `Bash` | `~/.local/bin/codex-block-worktree-commands` | `600` |
| `preToolUse` | `Bash` | `~/.local/bin/codex-block-git-push-main` | `600` |
| `preToolUse` | `apply_patch|Edit|Write` | `~/.local/bin/codex-block-main-branch-edits` | `600` |
| `postToolUse` | `apply_patch|Edit|Write` | `~/.local/bin/agent-current-spec-hook` | `600` |
| `sessionStart` | `startup|resume` | `~/.local/bin/codex-bind-tmux-pane` | `5` |
| `userPromptSubmit` | null | `~/.local/bin/codex-remind-repo-start-on-dev-prompt` | `600` |

### Why this approach

- It uses Codex's own `currentHash` instead of reverse-engineering hash input.
- It fits the repo's current model: this repo already owns both `hooks.json`
  and `config.toml`.
- It is narrow: only managed hook entries get trusted.
- It keeps user hooks subject to Codex's normal trust prompts.

## Alternatives Considered

### Add `trusted: true` to `hooks.json`

Rejected. Local Codex metadata shows trust state is not a handler field in
`hooks.json`. Adding an unsupported key would be speculative and may be ignored
or rejected by future schema validation.

### Hard-code trusted hashes in Ansible

Rejected. It would work only while hook order, hook content, and Codex's hash
algorithm stay unchanged. The bootstrap repo already updates hook entries over
time, so hard-coded hashes would become stale and recreate the trust prompt.

### Move hooks into managed/plugin requirements

Rejected for this slice. Codex distinguishes `trustStatus = "managed"` from
`trustStatus = "trusted"`, but this repo currently provisions user-level
machine config. Migrating hook ownership to plugin or requirements machinery
would be larger than the request and would change deployment boundaries.

## Components

### `roles/common/tasks/main.yml`

Add one task after the final managed `~/.codex/hooks.json` merge task:

- query Codex hook metadata
- filter to the managed hook manifest
- update `~/.codex/config.toml` hook state
- register `changed` / `unchanged`

The task should use `jq` for JSON filtering and keep TOML updates conservative,
matching the existing text-edit style used by nearby Codex config tasks.

### Tests

Add focused regression coverage for the hook trust update logic. A small helper
test is preferable to a broad playbook test because this behavior depends on
Codex's hook metadata shape.

The test should build a temporary Codex home with:

- a managed `hooks.json`
- an unrelated user hook
- an empty or preexisting `config.toml`

Then it should run the trust updater and verify:

- each managed hook has a matching `[hooks.state]` `trusted_hash`
- unrelated hook state is absent or preserved but not newly trusted
- a second run is unchanged
- changing a managed hook timeout or matcher changes the trusted hash
- stale managed keys are removed when a managed hook moves

## Data Flow

1. Provisioning writes or updates `~/.codex/hooks.json`.
2. The trust task asks Codex for normalized hook metadata for the current home.
3. The task filters metadata against the managed manifest.
4. The task writes trusted hashes to `~/.codex/config.toml`.
5. Future Codex sessions see `trustStatus = "trusted"` for those entries.

## Error Handling

- If Codex is unavailable, fail the task. A silent skip would leave hooks
  provisioned but untrusted, which is the user-visible failure this change is
  meant to remove.
- If `hooks/list` returns warnings or errors for `~/.codex/hooks.json`, fail
  with that output.
- If a managed hook entry is missing from metadata, fail. That indicates drift
  between the merge tasks and the trust manifest.
- If `config.toml` is malformed enough that the updater cannot safely preserve
  it, fail rather than rewrite the file broadly.

## Testing And Verification

Use Red/Green TDD:

1. Red: add a regression test showing managed hook entries are not trusted when
   only `hooks.json` is written.
2. Green: implement the trust task/helper until the test passes.
3. Run the hook trust regression test twice to prove idempotence.
4. Run existing hook helper tests:
   - `bash roles/common/files/bin/codex-block-worktree-commands.test`
   - `bash roles/common/files/bin/codex-block-git-push-main.test`
   - `bash roles/common/files/bin/codex-block-main-branch-edits.test`
   - `bash roles/common/files/bin/agent-current-spec-hook.test`
5. Run `bin/provision --check` where supported.
6. Run `bin/provision` on a managed macOS host and confirm:
   - `codex app-server --listen stdio://` `hooks/list` reports
     `trustStatus = "trusted"` for all managed hooks
   - unrelated hooks are not auto-trusted
   - `~/.codex/config.toml` and `~/.codex/hooks.json` are `0600`

## Rollout

This is safe to roll out through normal provisioning. Existing manually trusted
hooks stay trusted. New or changed managed hooks become trusted automatically on
the next `bin/provision` run.

If rollback is needed, remove the trust task. Existing `[hooks.state]` entries
can remain because they only trust hashes for the current managed hook content;
Codex marks entries modified or untrusted when content no longer matches.

## Open Risks

- `hooks/list` is an app-server API, not a small standalone CLI command. If
  Codex changes that API, the task can fail. The mitigation is to fail loudly
  during provisioning instead of silently leaving hooks untrusted.
- The hook key includes array indexes, so insertion order matters. The trust
  task must refresh state after all hook merge tasks have completed.
- Auto-trusting managed hooks means a change to one of this repo's hook entries
  is trusted as soon as provisioning runs. That is acceptable because the repo
  owns these hook definitions and the implementation filters to the explicit
  managed manifest.
