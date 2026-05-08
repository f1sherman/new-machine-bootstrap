# `repo-start.d` Callback Hook

## Problem

`repo-end` already supports a `~/.local/bin/repo-end.d/*` callback hook for
external tools to react to lifecycle events. `repo-start` exposes no such
hook, so tools that need to act when work begins on a branch (notify a
status board, warm a cache, mark a ticket in progress, etc.) have no
extension point.

## Goal

Add a generic `repo-start.d` callback mechanism that mirrors the existing
`repo-end.d` mechanism. Independent of any specific use case.

## Behavior

- After `repo-start` finishes its core work (mode resolved, worktree set
  up, tmux state published) and before the final path output, iterate
  `~/.local/bin/repo-start.d/*` executables in lexical order.
- Each callback receives:
  - `--repo-dir <path>` — the resolved worktree or branch path
  - `--branch <branch>` — the branch name passed to repo-start
  - `--main-branch <main>` — resolved via `_worktree_main_branch`
  - `--status <created|existing|repaired>` — same value as the JSON
    `status` field
- Strict failure semantics: a non-zero callback causes `repo-start` to
  exit non-zero, mirroring `repo-end.d`. A failed callback prints
  `repo-start callback failed: <path>` to stderr.
- In `--print-path` and `--json` modes, callback stdout is redirected to
  stderr so it doesn't pollute the machine-readable output.
- If `~/.local/bin/repo-start.d` doesn't exist, the loop is a no-op.
- Callback stderr is unredirected.

## Architecture

A single new function `run_repo_start_callbacks` in
`roles/common/files/bin/repo-start`, structured exactly like
`run_repo_end_callbacks` in `roles/common/files/bin/repo-end:36-53`.
Called once per `main` invocation, near the end (after tmux publish,
before `printf '%s\n' "$path"`).

## Testing

`tests/repo-start-callbacks.sh` mirroring `tests/repo-end-callbacks.sh`:

1. No callback dir → repo-start succeeds, prints final path.
2. Two callbacks (`10-first.sh`, `20-second.sh`) → both run in
   lexical order with expected args.
3. Callback that prints to stdout in `--print-path` mode → final stdout
   is just the path; callback stdout appears on stderr.
4. Callback that exits non-zero → repo-start exits non-zero, stderr
   contains `repo-start callback failed:`.

CI: add a step to `.github/workflows/integration-test.yml` invoking
`bash tests/repo-start-callbacks.sh`.

## Out of scope

- Specific callback content (Jira, Slack, etc.) — those live in
  consuming repos.
- Provisioning a default `repo-start.d` directory. Hooks installed by
  consumer repos create the dir as needed.
- Changes to `repo-end.d` semantics.
