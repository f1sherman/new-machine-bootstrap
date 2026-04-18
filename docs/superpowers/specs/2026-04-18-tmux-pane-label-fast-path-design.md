---
date: 2026-04-18
topic: Reduce tmux pane-label fork cost without losing remote labels
status: approved
---

# Design: tmux pane-label fast path

## Goal

Reduce fork cost in the always-on tmux pane labels on hosts where fork/exec is
slow, while preserving the label behavior that is actually useful:

- local panes still show `branch dirname` or `dirname`
- SSH panes still show the remote host
- Codespaces panes still show the codespace name
- DevPod panes still show the workspace name

This should follow the same optimization pattern already used elsewhere in this
repository: shrink the hot path first, keep the structure simple, and only pay
for process inspection when it is genuinely needed.

## Non-goals

- No cache layer, background daemon, or new tmux state variables.
- No event-driven label invalidation system.
- No new visible command field in tmux chrome.
- No change to tmux session naming logic in `tmux-session-name`.
- No attempt to optimize `smart-upload`, popups, or unrelated shell startup in
  this work.
- No removal of the existing remote-label behavior.

## Background

Recent history in this repository already established the optimization style to
follow here:

- commit `48c28fd` reduced `tmux-session-name` fork count by folding more data
  into one existing tmux RPC and replacing `git`/`basename` forks with bash and
  direct `.git/HEAD` reads
- commit `7fbe024` continued that work and explicitly targeted fork cost under
  load
- commit `103d3a5` removed `pane-title-changed` entirely rather than trying to
  optimize a high-frequency hook storm
- commits `16f37c4` and `8bb5f22` replaced hot `ps | grep` checks with tmux
  native format checks where tmux already knew the answer
- commit `df00a78` removed `pane_current_command` from visible tmux chrome
  because the field was noisy and wrappers like DevPod could surface useless
  command names such as `ruby`

Current state:

- `roles/macos/templates/dotfiles/tmux.conf` and
  `roles/linux/files/dotfiles/tmux.conf` both render pane labels through:
  `#(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}")`
- `roles/common/files/bin/tmux-pane-label` already uses a direct `.git/HEAD`
  read for local git labels
- but it still unconditionally runs `ps -o args= -t "$pane_tty"` before it
  knows whether the pane is even a remote candidate

That unconditional `ps` is the remaining hot-path fork to remove.

## Design Summary

Keep the current structure:

- one shared helper script: `tmux-pane-label`
- one shared window-label consumer: `tmux-window-label`
- the same pane-border and window-label wiring in tmux

Change only the hot path:

1. Pass `#{pane_current_command}` into `tmux-pane-label` as an internal hint.
2. Do not display that command text anywhere.
3. Use the hint only to decide whether the pane is a remote candidate.
4. If the pane is clearly local, skip `ps` entirely and return the local label
   from `pane_current_path` plus direct `.git/HEAD` inspection.
5. Only if the pane is a remote candidate do the existing `ps`-based parsing to
   extract the precise SSH host, codespace name, or DevPod workspace.

This matches the repo’s existing pattern:

- tmux-native data first
- bash/direct file reads second
- `ps` only on the slower exceptional path

## Components

### 1. `tmux-pane-label` contract update

File: `roles/common/files/bin/tmux-pane-label`

Current input:

- `$1` = `pane_tty`
- `$2` = `pane_current_path`

New input:

- `$1` = `pane_tty`
- `$2` = `pane_current_path`
- `$3` = `pane_current_command`

The third argument is an internal classification hint only. It is never shown
in the returned label.

### 2. `tmux.conf` plumbing update

Both tmux config files should change their pane-label call from:

```tmux
#(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}")
```

to:

```tmux
#(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}" "#{pane_current_command}")
```

No other tmux status formatting changes are part of this work.

### 3. `tmux-window-label` plumbing update

`roles/common/files/bin/tmux-window-label` currently fetches:

- `window_id`
- `pane_active`
- `window_name`
- `pane_tty`
- `pane_current_path`

It should also fetch `pane_current_command` in the same tmux RPC and pass it as
the third argument to `tmux-pane-label`.

This follows the same pattern used in `tmux-session-name`: fold more needed
data into one existing tmux call instead of adding a second lookup.

## `tmux-pane-label` behavior

### Local fast path

If `pane_current_command` is clearly not a remote candidate, the script should:

1. skip `ps` entirely
2. compute the local label from `pane_current_path`
3. return immediately

Local output remains:

- git repo: `<branch> <dirname>`
- non-git dir: `<dirname>`

The existing direct `.git/HEAD` logic stays; no `git branch` subprocess is
introduced.

### Remote candidate path

If `pane_current_command` suggests the pane may be remote, the script should
run the existing `ps -o args= -t "$pane_tty"` inspection and preserve the
current remote behavior:

- `ssh user@box` -> `box`
- `gh codespace ssh ...` / `gh cs ssh ...` -> codespace name
- `devpod ssh <workspace>` -> workspace name

If the process inspection does not resolve to one of those remote cases, the
script should fall back to the same local label logic as the fast path.

### Candidate commands

The coarse candidate set should be intentionally small and biased toward
correctness:

- `ssh`
- `gh`
- `ruby`

Why `ruby` is included:

- commit `df00a78` documented that DevPod-related wrappers can surface `ruby`
  as `pane_current_command`
- this keeps DevPod remote labels working without putting `ps` back on every
  pane refresh

Trade-off:

- a local pane actively running a Ruby process may still hit the slower `ps`
  path
- that is acceptable because the hot idle/prompt path is still optimized, which
  is where most panes spend most of their time

## What stays the same

- visible pane labels
- visible window labels
- remote label parsing logic
- local branch detection output format
- the shared helper layout in `roles/common/files/bin/`
- the no-cache/no-daemon architecture

## What changes

- `ps` is no longer unconditional in `tmux-pane-label`
- tmux passes one extra native field, `pane_current_command`, into the helper
- `tmux-window-label` forwards that same field in its existing helper call

## Test Strategy

Add a dedicated shell test harness for `tmux-pane-label`.

Minimum cases:

1. local non-git directory with non-remote command -> returns `dirname`
2. local git directory with non-remote command -> returns `branch dirname`
3. plain SSH command -> returns host label
4. Codespaces command -> returns codespace name
5. DevPod command with `ruby` as hint -> still resolves workspace name
6. remote-candidate hint that is not actually remote -> falls back to local
   label
7. no label output includes `pane_current_command` text

The harness should stub `ps` so tests can assert whether the fast path did or
did not consult it.

## Manual Verification

After provisioning and reloading tmux:

1. local pane in a git repo still shows `branch dirname`
2. local pane in a non-git dir still shows `dirname`
3. SSH pane still shows the host
4. Codespace pane still shows the codespace name
5. DevPod pane still shows the workspace name
6. command text is not shown in pane or window labels

## Edge Cases

- **DevPod wrapper ambiguity.** `pane_current_command` is not trusted as the
  final answer; it is only a gate into the slower `ps` path.
- **Remote pane launched from a local repo.** The helper must not return early
  to the local branch/path label when the command hint says the pane may be
  remote.
- **Missing third argument.** The helper should treat a missing hint as
  conservative and still behave correctly, even if that means using the slower
  path.
- **Unknown remote wrappers.** Out of scope. This design preserves only the
  currently supported SSH, Codespaces, and DevPod cases.

## Success Criteria

1. Idle local panes no longer pay for `ps` on every label refresh.
2. SSH, Codespaces, and DevPod labels remain intact.
3. No command text reappears in pane or window labels.
4. The implementation stays within the current helper-based architecture.
