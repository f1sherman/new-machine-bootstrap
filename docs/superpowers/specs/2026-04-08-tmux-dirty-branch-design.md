---
date: 2026-04-08
topic: Show a dirty-branch indicator in the tmux status bar
status: draft
---

# Design: tmux status-left dirty-branch indicator

## Goal

When the working tree of the tmux pane's current directory is dirty, prepend
a `*` inside the parentheses that tmux already wraps around the branch name
in `status-left`. Clean working trees continue to render as `(main)`; dirty
working trees render as `(*main)`. Non-git directories and detached HEAD
continue to render nothing, matching current behaviour.

"Dirty" means: any modified, staged, or untracked file — equivalent to a
non-empty `git status --porcelain`. This matches the definition used by the
Claude Code `cc-git-branch-dirty` widget.

## Non-goals

- No change to the Claude Code `cc-git-branch-dirty` helper or its widget.
  This work is strictly additive and parallel to that feature.
- No ahead/behind-remote indicator. Only working-tree state is reflected.
- No change to tmux's `status-interval`, `status-right`, session switcher,
  or any unrelated tmux configuration.
- No unification with `cc-git-branch-dirty`. The two scripts have different
  input contracts (argv path vs stdin JSON) and output contracts
  (parenthesised with trailing space vs raw string) and they stay separate.

## Background

- Both `roles/macos/templates/dotfiles/tmux.conf` and
  `roles/linux/files/dotfiles/tmux.conf` currently share the same
  `status-left`:
  ```
  set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
  ```
  The yellow fragment runs inline shell every `status-interval` (5s). The
  shell `cd`s into the pane's path and prints `"($branch) "` or nothing.
- Other tmux helper scripts in `roles/common/files/bin/` follow a clear
  pattern: small shell scripts, one concern each, installed to
  `~/.local/bin/` by individual `copy` tasks in
  `roles/common/tasks/main.yml`. Examples: `tmux-host-tag`, `tmux-session-name`,
  `tmux-window-name`, `tmux-status-toggle`.
- The Claude Code dirty-branch widget (`cc-git-branch-dirty`, merged in
  commit `35d6d57`) already demonstrates the dirty-detection algorithm and
  established the convention that error paths should silently print nothing
  and exit 0 rather than surfacing as visible error text.

## Components

1. **New helper script** `roles/common/files/bin/tmux-git-branch` —
   takes a directory path as `$1`, prints `(*<branch>) ` / `(<branch>) ` /
   empty, always exits 0.
2. **New Ansible install task** in `roles/common/tasks/main.yml` — copies
   the script to `~/.local/bin/tmux-git-branch`, placed alongside the other
   tmux helper install tasks.
3. **Edits to both tmux configs** — `roles/macos/templates/dotfiles/tmux.conf`
   and `roles/linux/files/dotfiles/tmux.conf`. Replace the inline
   `#(branch=$(cd …) …)` fragment in `status-left` with a call to the new
   helper script. The `#[fg=yellow]` color prefix, the cyan path segment,
   and the `tmux-host-tag` suffix are untouched.

No changes to ccstatusline, `cc-git-branch-dirty`, any other role, or
Claude Code config. No platform gating — the script lives in the `common`
role, so macOS, Linux dev hosts, and Codespaces all install it.

## Helper script contract

File: `roles/common/files/bin/tmux-git-branch`
Installed as: `~/.local/bin/tmux-git-branch` (mode 0755)

**Input:** One positional argument `$1`, the directory to inspect. In
practice `status-left` will pass `"#{pane_current_path}"`. The quoting is
tmux's responsibility — by the time the script runs, `$1` is a single
argv element even if the path contains spaces.

**Output (stdout):** Exactly one of:

| Situation                                      | Output          |
| ---------------------------------------------- | --------------- |
| `$1` missing, empty, or not a directory        | *(empty)*       |
| Not inside a git worktree                      | *(empty)*       |
| On a detached HEAD (no current branch)         | *(empty)*       |
| On a branch, working tree clean                | `(<branch>) `   |
| On a branch, working tree dirty                | `(*<branch>) `  |

The trailing space is part of the contract. It matches what the current
inline shell fragment emits, so the `status-left` replacement is a drop-in
and no surrounding whitespace in `status-left` needs to change.

**Exit code:** Always `0`. Error paths (missing argv, bad cwd, git failure,
not a repo) all print nothing and exit 0, so a broken invocation never
surfaces as visible error text in the tmux status bar.

**Algorithm:**

1. Read `$1` into a local variable. If empty or not a directory, exit 0
   with no output.
2. `cd "$dir" 2>/dev/null` — on failure, exit 0.
3. `git rev-parse --is-inside-work-tree 2>/dev/null` — if the command fails
   or prints anything other than `true`, exit 0.
4. `branch=$(git branch --show-current 2>/dev/null)` — if empty (detached
   HEAD), exit 0.
5. `git status --porcelain 2>/dev/null` — if output is non-empty, mark
   dirty.
6. Print `(*${branch}) ` if dirty, else `(${branch}) `.

**Dependencies:** `git` only. Deliberately no `jq` dependency — the script
takes its input from argv, so the JSON-parsing machinery needed by
`cc-git-branch-dirty` is absent. `git` is always present on every platform
this script targets.

**Differences from `cc-git-branch-dirty`:**

| Aspect         | `cc-git-branch-dirty`         | `tmux-git-branch`               |
| -------------- | ----------------------------- | ------------------------------- |
| Input          | Claude Code status JSON stdin | Path in `$1`                    |
| Output format  | `*branch` or `branch`         | `(*branch) ` or `(branch) `     |
| Parens         | No                            | Yes (baked in)                  |
| Trailing space | No                            | Yes                             |
| Dependency     | `jq` + `git`                  | `git` only                      |
| Consumer       | ccstatusline custom widget    | tmux `status-left` interpolation|

Same core dirty-detection logic, different contracts.

## tmux.conf edits

Both files currently have this line (identical content):

```
set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

Replace with:

```
set -g status-left '#[fg=yellow]#($HOME/.local/bin/tmux-git-branch "#{pane_current_path}")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

**What stays the same:**

- `#[fg=yellow]` prefix (the branch segment is still yellow).
- `#[fg=cyan]#{b:pane_current_path} ` cyan path segment.
- `#[fg=white]#($HOME/.local/bin/tmux-host-tag)` host-tag suffix.
- The outer single quotes, `status-left-length 80`, `status-interval 5`,
  and every other setting in both files.

**What changes:**

- Only the yellow `#(...)` fragment: from an inline shell pipeline to a
  single call into `~/.local/bin/tmux-git-branch`.

**Template note (macOS only):** `roles/macos/templates/dotfiles/tmux.conf`
is a Jinja2 template. The replaced fragment contains no Jinja2
meta-characters (`"#{pane_current_path}"` is tmux syntax, `$HOME` is
shell), so no `{% raw %}` block is required. The `{% raw %}` blocks
elsewhere in the file (for `is_vim` and pane-swap bindings) are unaffected.

Both files receive the same replacement — the session-context-visibility
design in `docs/superpowers/specs/2026-04-04-session-context-visibility-design.md`
unified `status-left` between macOS and Linux, and this design keeps them
in lockstep.

## Ansible installation

File: `roles/common/tasks/main.yml`

Add one new task, placed alongside the other tmux helper install tasks
(currently near lines 186–220: `tmux-session-name`, `tmux-switch-session`,
`tmux-host-tag`, `tmux-window-name`, `tmux-status-toggle`). The natural
spot is right after `Install tmux-host-tag script` and before
`Install tmux-window-name script`, so the tmux-related helpers stay
contiguous:

```yaml
- name: Install tmux-git-branch script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-git-branch'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-git-branch'
    mode: 0755
```

Identical shape to every other bin-script install task in the file.

Neither the tmux.conf install tasks nor any other tasks need to change:

- `roles/macos` installs its `tmux.conf` via the existing `template:` task
  and will pick up the edit automatically.
- `roles/linux` copies its `tmux.conf` via the existing `copy:` task and
  will pick up the edit automatically.

## Test strategy

### Automated tests

A sibling bash harness at `roles/common/files/bin/tmux-git-branch.test`
following the same pattern as `cc-git-branch-dirty.test`: creates isolated
tmp git repos, invokes the script with various paths, asserts stdout.

Cases, ordered for red/green TDD:

1. Missing argument (`tmux-git-branch`) → empty output.
2. Empty argument (`tmux-git-branch ""`) → empty output.
3. Argument is a nonexistent directory → empty output.
4. Argument is a non-git directory → empty output.
5. Fresh repo on main, clean → `(main) `.
6. Modified tracked file → `(*main) `.
7. Staged change → `(*main) `.
8. Untracked file only → `(*main) `.
9. Detached HEAD → empty output.

The harness writes each test case's expected value with a literal trailing
space (where applicable) and compares against the captured stdout. It uses
`printf '%q'` to make trailing-space differences visible in failure output.

### Manual verification after provisioning

1. `bin/provision` completes successfully.
2. `ls -l ~/.local/bin/tmux-git-branch` shows the file exists and is
   executable.
3. `~/.local/bin/tmux-git-branch "$PWD"` prints the current worktree's
   status, e.g. `(feature/tmux-dirty-branch) ` or
   `(*feature/tmux-dirty-branch) `.
4. Reload tmux's config in a running session:
   `tmux source-file ~/.tmux.conf` (or kill and restart tmux).
5. In a tmux pane whose cwd is a dirty git repo, wait up to 5 seconds
   (status-interval), then observe that the status bar shows
   `(*branch)` in yellow.
6. In a clean repo, observe `(branch) `.
7. In `/tmp` or another non-git directory, observe no branch segment and
   no orphaned whitespace.

## Edge cases and decisions

- **Paths with spaces.** tmux passes `"#{pane_current_path}"` as a single
  quoted argv, and the script reads `"$1"` with proper quoting. Handled
  identically to the current inline shell.
- **Detached HEAD.** `git branch --show-current` prints empty, script
  exits 0 with no output. Matches current behaviour and matches
  `cc-git-branch-dirty`.
- **Submodules.** `git status --porcelain` reports dirty submodules as
  dirty in the parent, so a dirty submodule marks the parent dirty.
  Consistent with `cc-git-branch-dirty`. No special handling.
- **Large repos.** `git status --porcelain` is fast because it only stats
  the index. In pathological cases (100k+ tracked files) the status bar
  could briefly show the previous value if the command exceeds the
  5-second interval, but tmux's `#(...)` runs asynchronously in recent
  versions and does not block the bar. Start simple; revisit only if we
  see real lag.
- **Script not installed yet.** If the tmux config is loaded before
  provisioning, `#(...)` runs the command, hits "command not found", and
  the fragment renders as empty. Visible effect: the branch segment is
  absent until `bin/provision` installs the script. Acceptable.
- **`bin/provision` while tmux is running.** Existing tmux sessions cache
  their config; the new behaviour only applies after
  `tmux source-file ~/.tmux.conf` or after a new tmux session starts. The
  helper script is used by the old-config sessions too (once installed),
  but only via the new config line — so old sessions continue to use
  the inline shell until reloaded. Either state works; nothing breaks.
- **Codespaces and Linux dev hosts.** The script and task are in the
  `common` role, so every platform installs it. The Linux tmux.conf edit
  propagates via the existing `copy:` task in `roles/linux`.
- **Colour choice.** Yellow, inherited from the existing `#[fg=yellow]`
  prefix in `status-left`. The script outputs plain text; tmux applies
  the colour. No escape sequences emitted by the script.

## Success criteria

1. `bin/provision` installs the new script, updates both tmux configs,
   and leaves the rest of the system unchanged.
2. `roles/common/files/bin/tmux-git-branch.test` passes all nine cases.
3. In a running tmux pane whose cwd is a clean git repo, the status-left
   shows `(branch) ` in yellow.
4. In a dirty repo, it shows `(*branch) ` in yellow.
5. Outside a git repo or on detached HEAD, the branch segment is absent
   and the rest of the status bar (directory, host tag) renders normally.
6. The Claude Code `cc-git-branch-dirty` widget continues to behave
   unchanged.
