# tmux pane-local agent worktree state

**Status:** Approved
**Date:** 2026-04-10

## Goal

Show the active pane's Claude/Codex worktree branch, dirty state, and linked
worktree marker reliably in tmux even when the long-lived agent process stays
rooted in the base repository and only a tool subprocess moves into the
worktree.

The user should be able to glance at tmux and know:

- which branch the active pane's agent is currently working on
- whether that worktree is dirty
- whether that branch comes from a linked worktree

The cyan directory segment should continue to reflect `#{pane_current_path}`.

## Non-goals

- No changes to the upstream Superpowers plugin in `~/.codex/superpowers` or
  Claude marketplace installs.
- No attempt to infer mid-session worktree switches purely from deeper process
  trees. This was proven unreliable in local testing.
- No use of pane titles as the source of truth for worktree state.
- No changes to `status-right`, window naming, host tag logic, or unrelated
  tmux behavior.
- No requirement that this work outside tmux. Outside tmux the helper should
  quietly do nothing.

## Background

Current behavior in this repository:

1. Both tmux configs still render the branch fragment from
   `tmux-git-branch "#{pane_current_path}"`, so they only know about the
   pane's shell cwd.
2. The local shell helper `worktree-start` creates linked worktrees, copies
   `.coding-agent`, copies `.claude/settings.local.json` when needed, runs
   `mise trust`, and then `cd`s into the new worktree.
3. Global Claude/Codex instructions are provisioned from this repo via
   `roles/common/tasks/main.yml`, with `~/.codex/AGENTS.md` symlinked to
   `~/.claude/CLAUDE.md`.
4. Claude already has local hooks in this repo for "working on/off" state,
   which proves this environment already uses local sidecar integration rather
   than relying exclusively on upstream plugin behavior.

The critical observed failure:

- Creating or switching worktrees from inside an already-running Codex session
  does **not** move the long-lived Codex process into the worktree.
- The worktree exists and child tool processes can have cwd inside it, but the
  parent Codex process on the pane tty stays rooted in the base repository.
- Therefore tmux cannot reliably discover the active agent worktree from argv
  or parent-process cwd alone after an in-session worktree switch.

That means the current heuristic approach is insufficient for the user's real
workflow. A reliable design needs an explicit pane-scoped signal.

## Design

### Summary

Use pane-local tmux options as the authoritative source of agent worktree
state, managed by a new local helper script. tmux status rendering reads that
explicit state first and falls back to existing heuristics only when the pane
has no valid explicit state.

This keeps all behavior in the bootstrap repo:

- no upstream Superpowers patching
- no dependence on undocumented Claude/Codex runtime behavior
- no title parsing hacks

### Components

1. **New helper script**: `roles/common/files/bin/tmux-agent-worktree`
2. **New status helper**: `roles/common/files/bin/tmux-agent-pane-status`
3. **Install tasks** in `roles/common/tasks/main.yml`
4. **tmux config updates** in:
   - `roles/macos/templates/dotfiles/tmux.conf`
   - `roles/linux/files/dotfiles/tmux.conf`
5. **Shell helper integration** in:
   - `roles/common/templates/dotfiles/zshrc`
   - `roles/macos/templates/dotfiles/bash_profile`
6. **Global agent instruction update** in the managed `~/.claude/CLAUDE.md`
   content in `roles/common/tasks/main.yml`

No upstream plugin files are edited.

## Pane-local tmux state contract

The source of truth is a pair of pane-local tmux options:

- `@agent_worktree_path`
- `@agent_worktree_pid`

They are written against a specific pane with:

```bash
tmux set-option -pt "$TMUX_PANE" @agent_worktree_path "$path"
tmux set-option -pt "$TMUX_PANE" @agent_worktree_pid "$pid"
```

They are read with:

```bash
tmux show-options -pv -t "$pane_id" @agent_worktree_path
tmux show-options -pv -t "$pane_id" @agent_worktree_pid
```

This state is authoritative only for the targeted pane. It does not leak to
other panes, windows, or sessions.

### Why pane-local tmux options

- They are already in tmux, which is the display system consuming the state.
- They are naturally scoped to a single pane.
- They survive long enough to be useful but are easy to ignore when stale.
- They avoid filesystem cleanup and file-locking problems that a state-file
  approach would introduce.
- They do not overload pane titles, which this environment already uses for
  session naming and Ghostty tab title updates.

## `tmux-agent-worktree` helper contract

File: `roles/common/files/bin/tmux-agent-worktree`  
Installed as: `~/.local/bin/tmux-agent-worktree`

### Commands

#### `set <absolute-path>`

Writes explicit pane-local agent worktree state for the current tmux pane.

Behavior:

1. Require `TMUX` and `TMUX_PANE`. If not running inside tmux, exit 0.
2. Require a non-empty absolute path argument. If invalid, exit 0.
3. Resolve the current pane tty from tmux.
4. Detect the active Claude/Codex PID on that tty using the same foreground
   preference logic used by `tmux-agent-pane-status`.
5. If no active Claude/Codex process is found, exit 0 without writing state.
6. Validate that the provided path exists and is inside a git worktree.
7. Write `@agent_worktree_path` and `@agent_worktree_pid` for `TMUX_PANE`.

The helper does not need to determine branch or dirty state. It only publishes
pane-scoped identity and path.

#### `sync-current`

Synchronizes explicit pane state from the current shell cwd.

Behavior:

1. If `$PWD` is a linked worktree on a normal branch, behave like
   `set "$PWD"`.
2. Otherwise clear explicit state for the pane.

This is the shell-helper integration point after `cd` into or out of a
worktree.

#### `clear`

Removes pane-local explicit state:

```bash
tmux set-option -pt "$TMUX_PANE" -u @agent_worktree_path
tmux set-option -pt "$TMUX_PANE" -u @agent_worktree_pid
```

If not inside tmux, exit 0.

### Failure behavior

All commands exit 0 on failure or missing context and print nothing. The tmux
bar must never show script errors.

## `tmux-agent-pane-status` behavior

File: `roles/common/files/bin/tmux-agent-pane-status`  
Installed as: `~/.local/bin/tmux-agent-pane-status`

This helper replaces direct use of `tmux-git-branch` in `status-left`.

### Inputs

- `$1`: pane id
- `$2`: pane tty
- `$3`: pane current path

### Resolution order

#### 1. Explicit pane state

Read `@agent_worktree_path` and `@agent_worktree_pid` for the target pane and
treat them as authoritative only when all of the following are true:

1. The pane currently has an active Claude/Codex process.
2. The active agent PID matches the stored `@agent_worktree_pid`.
3. The stored path exists.
4. The stored path is inside a git worktree.
5. The stored path is on a named branch.

If all checks pass, render branch state from that stored path.

#### 2. Existing heuristics

If explicit state is absent or stale, fall back to heuristic detection:

1. Codex `--cd` / `-C` argv
2. agent process cwd
3. finally `pane_current_path`

The final fallback to `pane_current_path` behaves like the existing
`tmux-git-branch` behavior and must not append `[wt]`.

### Rendering rules

When rendering from an explicit or heuristic agent path:

| Situation | Output |
| --- | --- |
| clean branch in linked worktree | `(<branch>) [wt] ` |
| dirty branch in linked worktree | `(*<branch>) [wt] ` |
| clean branch in non-linked repo/worktree | `(<branch>) ` |
| dirty branch in non-linked repo/worktree | `(*<branch>) ` |
| detached HEAD | *(empty)* |
| nongit path | *(empty)* |

The cyan directory segment remains `#{b:pane_current_path}`.

### Stale explicit state handling

Explicit state is stale when:

- stored PID does not match the active pane agent PID
- stored path no longer exists
- stored path is no longer a git worktree
- pane no longer has an active Claude/Codex process

Stale state is ignored, not surfaced. The helper simply falls through to
heuristic mode.

## Shell helper integration

### `worktree-start`

After the final `cd "$path"`, call:

```bash
tmux-agent-worktree sync-current >/dev/null 2>&1 || true
```

This is what makes local manual and agent-driven uses of `worktree-start`
publish pane state without touching upstream Superpowers.

### `worktree-merge`, `worktree-delete`, `worktree-done`

After they `cd` back to the main worktree, call the same `sync-current`
command. Since `$PWD` is no longer the linked worktree, this clears or resets
the pane state appropriately.

### bash_profile parity

The macOS bash versions of the same helpers receive the same integration so
the contract is consistent across shells.

## Global Claude/Codex instruction update

Add one concise instruction block to the managed `~/.claude/CLAUDE.md`
content in `roles/common/tasks/main.yml`. Because `~/.codex/AGENTS.md`
symlinks to that file, the same instruction will apply to both Claude and
Codex.

The instruction should say, in substance:

- when running inside tmux and you create or switch to a worktree, immediately
  publish it with `tmux-agent-worktree set <absolute-path>`
- when you return from that worktree to the base repository, run
  `tmux-agent-worktree clear`
- prefer the local `worktree-start` helper when available, since it already
  performs the local environment setup and publishes tmux state automatically

This instruction is intentionally short and local. It augments upstream
Superpowers behavior without forking or rewriting the upstream skills.

## tmux configuration

Update both tmux configs so `status-left` calls the new helper:

```tmux
set -g status-left '#[fg=yellow]#($HOME/.local/bin/tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

Everything else in `status-left` stays unchanged:

- yellow branch fragment
- cyan directory fragment
- host tag suffix

The helper must work on both macOS and Linux. No platform-specific branching
in tmux config is needed.

## Why this avoids upstream conflicts

- Upstream Superpowers stays untouched.
- tmux state publication lives in repo-managed local helpers and global
  local instructions.
- If upstream Superpowers changes how it describes worktree creation, local
  `worktree-start` integration still works.
- If an agent ignores the explicit instruction, heuristic fallback still
  covers startup cases such as `codex --cd` or a process whose cwd already
  matches the worktree.

This is a sidecar integration, not a fork.

## Verification

### Automated tests

Add bash tests for both helpers.

#### `tmux-agent-worktree.test`

Cases:

1. `set` outside tmux exits 0 and writes nothing.
2. `set` with no active agent on the pane exits 0 and writes nothing.
3. `set` with invalid path exits 0 and writes nothing.
4. `set` with active agent and valid worktree writes pane-local path and pid.
5. `clear` removes both pane-local options.
6. `sync-current` sets state when `$PWD` is a linked worktree on a branch.
7. `sync-current` clears state when `$PWD` is nongit or detached HEAD.

#### `tmux-agent-pane-status.test`

Cases:

1. explicit pane state with matching pid overrides pane cwd
2. stale pid is ignored and falls back to heuristics
3. missing path is ignored and falls back to heuristics
4. explicit linked worktree renders `[wt]`
5. explicit dirty worktree renders `*`
6. detached HEAD explicit path renders empty branch fragment
7. no explicit state falls back to Codex `--cd`
8. no explicit state falls back to agent cwd
9. no explicit state falls back to `pane_current_path`

### Live verification

1. Provision the updated dotfiles.
2. Reload tmux config.
3. In a pane with an already-running Codex session rooted on the base repo,
   create or switch to a worktree and publish explicit pane state with
   `tmux-agent-worktree set <absolute-path>`.
4. Confirm the status bar shows the worktree branch and `[wt]` while the cyan
   directory stays on the pane cwd.
5. Dirty the worktree and confirm the leading `*` appears.
6. Clear the explicit pane state and confirm the status bar falls back to the
   heuristic/base-repo view.
7. Reuse the same pane with a different Claude/Codex process and confirm stale
   state is ignored because the pid no longer matches.

## Out of scope

- Any upstream Superpowers PR or marketplace plugin change.
- Changing Claude's existing working-on/off title hooks into state transport.
- Full session wrappers around `claude` or `codex` startup.
- Capturing arbitrary internal directory changes outside explicit worktree
  transitions.
