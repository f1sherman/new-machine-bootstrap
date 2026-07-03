# Pi Managed Hooks Parity Design

## Problem

Pi uses TypeScript extensions for tool-call and lifecycle behavior, while Claude Code and Codex use managed hook commands. Several guardrails existed only in Claude/Codex hooks, so Pi sessions could miss policies that prevent unsafe or workflow-breaking actions.

## Scope

Bring the existing Pi `managed-hooks.ts` extension to parity for these policies:

- Block raw `git commit` and direct agents to `_commit`.
- Block direct pushes to `main`.
- Block `git add -f` / `--force` for `docs/superpowers/...` paths.
- Track the current edited superpowers spec path in tmux pane state.

Already-covered Pi behaviors stay unchanged: repo-start reminders, tmux subject reminders, worktree/branch creation blocking, and edit/write blocking on `main`.

## Approach

Extend `roles/common/files/pi/extensions/managed-hooks.ts` rather than adding shell-hook emulation. This keeps Pi behavior in Pi's native extension model and avoids duplicating Claude/Codex hook installation mechanics.

The Bash tool-call path will return deny responses for raw commit, push-main, and forced superpowers-docs additions. The edit/write tool-call path will continue checking main-branch safety, then set `@agent_current_spec_path` when the target path is a single `docs/superpowers/specs/*.md` file.

## Testing

Expand `tests/pi-managed-hooks.sh` as the behavior contract. It loads the extension with a fake Pi API and asserts both blocked and allowed cases for each policy, including tmux state updates for spec tracking.
