# Codex worktree command hook

**Status:** Approved
**Date:** 2026-04-14

## Goal

Prevent Codex CLI from creating or deleting git worktrees through raw
`git worktree add` and `git worktree remove` commands. Codex should use the
bootstrap-managed worktree helpers instead.

After this change:

- bootstrap-managed Codex environments use a user-level Codex hook to deny raw
  worktree add/remove Bash commands
- the supported workflow is `worktree-start` and `worktree-delete`
- machine-level ownership stays entirely inside `new-machine-bootstrap`
- no repo-specific application repository changes are required

## Non-goals

- No changes in application repositories such as
  `home-network-provisioning`.
- No repo-local `.codex/hooks.json` files in individual projects.
- No changes to the managed global `CLAUDE.md` / `AGENTS.md` content for this
  feature.
- No attempt to rewrite a blocked Codex Bash command into a helper command.
- No blocking of unrelated `git worktree` subcommands such as `list`,
  `prune`, or `lock`.
- No enforcement outside Codex's Bash tool path. Manual shell use outside
  Codex remains unchanged.

## Background

Current state in this repository:

1. `worktree-start`, `worktree-delete`, `worktree-done`, and `worktree-merge`
   live as large shell functions in:
   - `roles/common/templates/dotfiles/zshrc`
   - `roles/macos/templates/dotfiles/bash_profile`
2. The real worktree logic is duplicated across zsh and bash templates.
3. `tmux-agent-worktree` is already an installed helper script in
   `roles/common/files/bin/`, which shows this repo already supports
   executable helpers for worktree-related behavior.
4. Codex configuration is already managed here through `~/.codex/config.toml`
   updates in `roles/common/tasks/main.yml`.

The user originally considered moving this behavior into
`home-network-provisioning`, but that would create split ownership:

- `new-machine-bootstrap` would still own dotfiles, Codex config, and machine
  bootstrap
- another repo would own the worktree policy those machine-level configs rely
  on

That layering is backwards. The worktree helpers and Codex hook policy are
machine bootstrap concerns, so they should stay in this repository.

There is also a current Codex runtime constraint from the official docs:

- hooks are loaded from `~/.codex/hooks.json` or `<repo>/.codex/hooks.json`
- hooks require `[features] codex_hooks = true`
- `PreToolUse` currently only intercepts Bash
- `PreToolUse` can deny a command, but it cannot reliably rewrite that command
  into another command today

That means the correct design is a guardrail hook that blocks raw worktree
commands and tells Codex to use the supported helper commands.

## Design

### Summary

Keep all ownership in `new-machine-bootstrap`.

Refactor the existing shell-function worktree behavior into installed helper
scripts under `roles/common/files/bin/`, keep only thin shell wrappers in the
dotfile templates, and add a user-level Codex `PreToolUse` hook that blocks
raw `git worktree add` and `git worktree remove`.

The result is:

- one source of truth for worktree behavior
- no duplicated large worktree implementations in zsh and bash templates
- a Codex-native guardrail for the exact misuse the user wants to prevent
- no dependence on global instruction-text changes

### Components

1. Installed helper scripts in `roles/common/files/bin/`
2. Thin wrapper functions in shell templates
3. Codex config enablement in `~/.codex/config.toml`
4. User-level `~/.codex/hooks.json`
5. A dedicated hook helper script for command blocking

## Installed helper scripts

### Scripts owned here

This design moves the main worktree behavior into installed executables:

- `worktree-start`
- `worktree-delete`
- `worktree-done`
- `worktree-merge`
- `codex-block-worktree-commands`
- existing `tmux-agent-worktree` stays here

Installed location:

- `~/.local/bin/<script-name>`

### Why convert shell functions into scripts

- Removes the current duplicated worktree logic between zsh and bash.
- Makes the supported worktree behavior callable from Codex, shell wrappers,
  and tests through the same implementation.
- Keeps the shell templates small and easier to maintain.
- Fits the existing bootstrap pattern already used for helpers such as
  `tmux-agent-worktree`, `git-switch-branch`, and related tools.

## Script contracts

### `worktree-start`

The installed `worktree-start` script becomes the source of truth for:

- parsing branch/path/start-point arguments
- validating repository state
- creating the linked worktree and branch
- copying `.coding-agent`
- copying `.claude/settings.local.json` when needed
- trusting the new worktree for Claude when supported
- running `mise trust` for the new worktree

The executable does **not** attempt to change the parent shell's current
directory.

Expected behavior:

- default mode creates the worktree and prints human-readable success output
- `--print-path` creates the worktree and prints only the absolute worktree
  path for shell-wrapper consumption

This keeps the `cd` behavior out of the executable while preserving the
existing user-facing workflow through wrappers.

### `worktree-delete`, `worktree-done`, and `worktree-merge`

These scripts become the source of truth for their current validation and git
operations. They do not own parent-shell state changes.

This preserves the current architecture:

- executable owns git logic
- shell wrapper owns shell-local behavior when needed

### `tmux-agent-worktree`

No ownership move is required because this script is already in the correct
layer. It stays as an installed helper in this repository.

The only required change is that shell wrappers continue calling it after
entering a new worktree so the tmux pane state remains accurate.

## Shell wrapper design

The dotfile templates keep the existing user-facing command names, but they
become thin wrappers instead of hosting the full implementation.

Affected files:

- `roles/common/templates/dotfiles/zshrc`
- `roles/macos/templates/dotfiles/bash_profile`

### Wrapper rules

- Wrapper names stay the same: `worktree-start`, `worktree-delete`,
  `worktree-done`, `worktree-merge`.
- Wrappers call the installed script using an absolute path in `~/.local/bin`
  so the function name can safely match the executable name.
- `worktree-start` is the only wrapper that needs special handling:
  - call the executable in `--print-path` mode
  - `cd` into the returned path in the parent shell
  - run `tmux-agent-worktree sync-current`
- The other wrappers can delegate directly to their installed executables.

### Why thin wrappers

`worktree-start` still needs a shell function because only a shell function can
change the parent interactive shell's working directory. That is a shell UX
concern, not a reason to keep the entire worktree implementation embedded in
two dotfile templates.

## Codex hook design

### Location and enablement

This is a global machine-level guardrail, so it uses the user-level Codex hook
location:

- `~/.codex/hooks.json`

It is enabled by setting:

```toml
[features]
codex_hooks = true
```

in `~/.codex/config.toml`.

This should be managed by `roles/common/tasks/main.yml`, alongside the
repository's other Codex configuration.

### Why user-level and not repo-local

The user wants Codex CLI to follow this policy generally, not just inside one
project. That makes `~/.codex/hooks.json` the correct layer.

Repo-local hooks would create inconsistent behavior across repositories and
would put a machine bootstrap policy into application repos.

### Hook file management

The design should update `~/.codex/hooks.json` idempotently so this repo's
guardrail hook can coexist with other future Codex hooks.

If the file already exists, implementation should merge this repository's
managed `PreToolUse` hook entry into the existing JSON instead of overwriting
unrelated hook entries. If the file does not exist, implementation should
create it with the managed hook content.

## Hook helper behavior

### Installed helper

Add a new installed helper:

- `roles/common/files/bin/codex-block-worktree-commands`

Installed as:

- `~/.local/bin/codex-block-worktree-commands`

### Trigger

Register this helper as a `PreToolUse` hook for the `Bash` matcher.

### Input

The helper reads the Codex hook JSON payload from `stdin` and inspects:

- `tool_input.command`

### Blocking policy

The helper denies Bash commands that directly invoke:

- `git worktree add`
- `git worktree remove`

The check should cover common variants such as:

- `git worktree add ...`
- `git worktree remove ...`
- `env FOO=bar git worktree add ...`
- `bash -lc 'git worktree remove ...'`

The helper should **not** block:

- `worktree-start ...`
- `worktree-delete ...`
- `git worktree list`
- `git worktree prune`
- other unrelated git commands

### Output

On a blocked command, the helper returns the documented `PreToolUse` deny JSON
shape with a reason that explicitly tells Codex which helper to use:

- for add: use `worktree-start`
- for remove: use `worktree-delete`

No command rewriting is attempted.

### Why this works with helper scripts

When Codex runs `worktree-start`, the Bash tool invocation seen by Codex is
`worktree-start ...`, not the nested `git worktree add` subprocesses that the
script runs internally. That means the guardrail blocks raw direct worktree
commands from Codex without preventing the approved helper scripts from doing
their job.

## No `CLAUDE.md` changes

This design intentionally does not change the managed global `CLAUDE.md` /
`AGENTS.md` content for this feature.

The requested enforcement should come from:

- the installed helper commands
- the Codex hook
- existing shell UX

That keeps this change focused and avoids turning a command-policy guardrail
into an instruction-text migration.

## Platform scope

This behavior belongs in the common bootstrap layer and should apply anywhere
this repo provisions Codex and the shared shell environment:

- macOS
- Linux dev hosts
- Codespaces

Windows is out of scope because current Codex hooks are disabled there and this
repository does not target Windows as a managed platform.

## Verification

Implementation is complete only when all of the following are verified:

1. `~/.codex/config.toml` enables `codex_hooks`.
2. `~/.codex/hooks.json` contains the managed `PreToolUse` Bash hook entry.
3. A raw Codex-issued `git worktree add ...` command is denied with the
   expected reason.
4. A raw Codex-issued `git worktree remove ...` command is denied with the
   expected reason.
5. `worktree-start <branch>` still creates a worktree and lands the interactive
   shell in it.
6. `worktree-delete` still performs its existing safe deletion behavior.
7. tmux worktree state still updates correctly after `worktree-start`.

## Testing

### Automated

- Add script-level regression tests for the new hook helper.
- Add regression coverage for the extracted worktree helper behavior that is
  moving out of shell templates.
- Keep the existing `tmux-agent-worktree` behavior covered.

The preferred style is the repository's existing helper-adjacent shell test
pattern used for scripts under `roles/common/files/bin/`.

### Empirical

After provisioning on a real managed environment, run a real Codex session and
confirm:

- raw `git worktree add/remove` commands are blocked
- `worktree-start` succeeds
- `worktree-delete` succeeds

## Risks and mitigations

### Hook coverage is incomplete

Risk:
`PreToolUse` currently only intercepts Bash tool calls and is not a full
security boundary.

Mitigation:
Treat the hook as a guardrail, not as perfect sandbox enforcement. Keep the
approved helper commands installed and documented by name in the shell
environment.

### Script extraction changes behavior

Risk:
Moving logic out of shell functions could accidentally regress `worktree-start`
or tmux sync behavior.

Mitigation:
Keep `worktree-start` wrapper behavior explicit: create via executable, `cd`
in the parent shell, then sync tmux state. Verify this empirically after
provisioning.

### Hook file ownership drift

Risk:
Managing `~/.codex/hooks.json` carelessly could overwrite unrelated future
hooks.

Mitigation:
Update the hook file idempotently and keep this feature scoped to one clearly
named hook helper entry.
