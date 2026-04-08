---
date: 2026-04-07
topic: Show a dirty-branch indicator in the Claude Code statusline
status: draft
---

# Design: Claude Code statusline dirty-branch indicator

## Goal

When the working tree of the current repository is dirty, prepend a `*` to the
git branch name shown in the Claude Code statusline. Clean working trees show
the branch name alone. Directories outside a git worktree show nothing for this
widget (no change from today's behaviour).

"Dirty" means: any modified, staged, or untracked file — equivalent to a
non-empty `git status --porcelain`.

## Non-goals

- No change to the tmux status bar. It already shows the current branch in
  yellow from `status-left`; this design intentionally leaves tmux alone.
- No ahead/behind-remote indicator. Only working-tree state is reflected.
- No replacement for the existing `git-branch` ccstatusline widget type — we
  are not editing the upstream ccstatusline package.

## Background

- ccstatusline is configured from `roles/common/files/config/ccstatusline/settings.json`
  and installed as `~/.config/ccstatusline/settings.json` by
  `roles/common/tasks/main.yml:306`.
- ccstatusline's built-in `git-branch` widget (upstream `src/widgets/GitBranch.ts`)
  only renders `branch` or `⎇ branch`. It has no dirty-state option, so a
  custom-command widget is required.
- Custom-command widgets run via `execSync` with the full Claude Code status
  JSON piped on stdin; `.cwd` (and `.workspace.current_dir` as fallback) give
  the active working directory. Default timeout is 1000ms. Empty stdout hides
  the widget (including its powerline separator). These facts are verified in
  upstream `src/widgets/CustomCommand.tsx` and `src/types/StatusJSON.ts`.
- The existing `model` widget already follows this pattern with an inline jq
  command, confirming custom-command widgets work in the current config.
- tmux's `status-left` already renders the branch in yellow, so using yellow
  for this widget keeps the two status lines visually consistent.

## Components

Three artefacts:

1. **New helper script** `roles/common/files/bin/cc-git-branch-dirty` —
   reads the Claude status JSON on stdin, emits `*<branch>` / `<branch>` /
   empty.
2. **Widget config change** to `roles/common/files/config/ccstatusline/settings.json` —
   adds one `custom-command` widget at the start of line 0.
3. **New Ansible task** in `roles/common/tasks/main.yml` — installs the
   helper script into `~/.local/bin/cc-git-branch-dirty` using the same
   `copy` pattern as the other bin scripts in the file.

No changes to the tmux configs, the macOS/Linux/Codespaces/dev_host roles, or
to ccstatusline's upstream package. No changes to the Claude settings merging
logic.

## Helper script contract

File: `roles/common/files/bin/cc-git-branch-dirty`
Installed as: `~/.local/bin/cc-git-branch-dirty` (mode 0755)

**Stdin:** Claude Code status JSON. Relevant fields: `.cwd`, with
`.workspace.current_dir` as a fallback.

**Stdout:** Exactly one of:

| Situation                                      | Output     |
| ---------------------------------------------- | ---------- |
| `cwd` missing, empty, or doesn't exist         | *(empty)*  |
| `cwd` is not inside a git worktree             | *(empty)*  |
| Inside a git worktree but on a detached HEAD   | *(empty)*  |
| On a branch, working tree clean                | `<branch>` |
| On a branch, working tree dirty                | `*<branch>`|

Empty output causes ccstatusline to hide the widget (including its surrounding
powerline separator), so non-git directories keep the current two-widget look.

**Exit code:** Always `0`. Any error path (jq parse failure, cd failure, git
failure, permission denied) prints nothing and exits 0. This prevents a broken
git invocation from surfacing `[Exit: N]` or `[Error]` in the user's
statusline.

**Algorithm:**

1. Read stdin into a variable.
2. Extract `cwd` with `jq -r '.cwd // .workspace.current_dir // empty'`. If
   the result is empty or not a directory, exit 0 with no output.
3. `cd` into `cwd`. On failure, exit 0 with no output.
4. `git rev-parse --is-inside-work-tree` — if the command fails or prints
   anything other than `true`, exit 0 with no output.
5. `git branch --show-current` — if output is empty (detached HEAD), exit 0
   with no output.
6. `git status --porcelain` — if output is non-empty, set a `dirty` flag.
7. Print `*${branch}` if dirty, else `${branch}`.

**Dependencies:** `jq` (installed on macOS via Homebrew and on Linux via apt
in the linux role), `git` (always present). No other dependencies.

## ccstatusline widget config

File: `roles/common/files/config/ccstatusline/settings.json`

Add one entry at the front of `lines[0]`:

```json
{
  "id": "git-branch-dirty",
  "type": "custom-command",
  "color": "yellow",
  "commandPath": "$HOME/.local/bin/cc-git-branch-dirty"
}
```

Resulting `lines[0]`:

```json
[
  {
    "id": "git-branch-dirty",
    "type": "custom-command",
    "color": "yellow",
    "commandPath": "$HOME/.local/bin/cc-git-branch-dirty"
  },
  {
    "id": "1",
    "type": "custom-command",
    "color": "cyan",
    "commandPath": "jq -r '.model.id // .model // \"\" | gsub(\"^claude-\"; \"\") | gsub(\"-[0-9]{8}$\"; \"\") | gsub(\"(?<a>[a-z]+)-(?<v>[0-9]+)-(?<m>[0-9]+)\"; \"\\(.a)\\(.v).\\(.m)\")'"
  },
  {
    "id": "2",
    "type": "context-percentage-usable",
    "color": "brightBlack",
    "rawValue": true,
    "metadata": { "inverse": "true" }
  }
]
```

**Choices:**

- **Full absolute path** (`$HOME/.local/bin/cc-git-branch-dirty`) — ccstatusline
  is launched by the Claude Code process, and we don't want to assume what's on
  its inherited `PATH`. execSync performs shell variable expansion, so `$HOME`
  works.
- **`color: "yellow"`** matches the branch colour in `status-left` of both
  `roles/macos/templates/dotfiles/tmux.conf` and
  `roles/linux/files/dotfiles/tmux.conf`.
- **No `timeout` override** — the default 1000ms is well above what
  `git status --porcelain` needs on typical repos.
- **No `maxWidth`** — branch names are short, and truncation would hide the
  leading `*`.
- **Placed first** on the line so the dirty indicator is visually prominent
  and closest to where the eye lands.
- **String id `git-branch-dirty`** is self-documenting; ccstatusline treats
  widget ids as opaque strings.

## Ansible installation

File: `roles/common/tasks/main.yml`

Add a new task after the `Install claude-trust-directory script` task
(currently at lines 221–226), grouping it with the other Claude-related
helpers:

```yaml
- name: Install cc-git-branch-dirty script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/cc-git-branch-dirty'
    src: '{{ playbook_dir }}/roles/common/files/bin/cc-git-branch-dirty'
    mode: 0755
```

No changes to the `Install ccstatusline widget configuration` task
(currently at lines 306–310): it already copies the widget JSON on every
provision run, and the widget addition lives inside the source file.

## Test strategy

### Automated tests for the helper script

A small bash harness at
`roles/common/files/bin/cc-git-branch-dirty.test` (not installed to
`~/.local/bin`, lives next to the script for discoverability). It creates
temporary git repositories, pipes synthesised JSON into the script, and
asserts the output.

Cases, ordered for red/green TDD:

1. Not in a git repo (`cwd=/tmp` or a known non-repo tmpdir) → empty output.
2. Fresh repo with one commit, no changes → `<default-branch>`.
3. Modified tracked file → `*<branch>`.
4. Staged change (`git add` of a modified file, no commit) → `*<branch>`.
5. Untracked file only → `*<branch>`.
6. Detached HEAD (checkout of the commit SHA) → empty output.
7. JSON with no `cwd` key and no `workspace.current_dir` (`{}`) → empty.
8. `cwd` pointing at a nonexistent directory → empty.
9. JSON with only `workspace.current_dir` → behaves like case 2 or 3.

The test harness exits non-zero on any failure and prints a diff of expected
vs actual. It avoids `init.defaultBranch` portability issues by configuring
`git init -b main` explicitly inside each case.

### Manual verification after provisioning

1. Run `bin/provision` on macOS — expect success.
2. Open Claude Code in a clean git repo — statusline shows `main` in yellow
   at the far left.
3. Touch a tracked file — statusline shows `*main`.
4. `git stash` (or `git restore`) — statusline returns to `main`.
5. `cd /tmp` and open Claude Code — the widget is absent (only the model and
   context-percentage widgets appear).
6. `git checkout <sha>` (detached HEAD) and open Claude Code — the widget
   is absent.

## Edge cases and decisions

- **Submodules and linked worktrees.** `git rev-parse --is-inside-work-tree`
  returns `true` in both, and `git status --porcelain` in a parent repo
  reports dirty submodules, so a dirty submodule marks the parent dirty.
  No special handling.
- **Large repos.** `git status --porcelain` is typically fast because it only
  stats the index. If users ever see `[Timeout]`, switch the widget to a
  higher timeout or swap the script to `git diff-index --quiet HEAD --` plus
  a targeted untracked check. Not worth doing preemptively.
- **Codespaces and dev hosts.** The helper lives in the `common` role, so
  Codespaces, Linux dev hosts, and macOS all install it automatically. No
  platform gating.
- **`jq` availability.** Installed on macOS via `roles/macos` Homebrew
  packages and on Linux via `roles/linux` apt packages. Safe to hard-depend.
- **`PATH` of ccstatusline.** Handled by using an absolute path
  (`$HOME/.local/bin/cc-git-branch-dirty`) in the widget config.
- **Colour.** Yellow. No bold. No background. Matches tmux.
- **Widget ordering.** Dirty-branch first, then model, then
  context-percentage. Swap order later if it feels wrong.

## Success criteria

1. Running `bin/provision` on macOS installs the new script and updates
   `~/.config/ccstatusline/settings.json` with the new widget entry.
2. `roles/common/files/bin/cc-git-branch-dirty.test` passes all nine cases.
3. In a clean repo, the Claude Code statusline shows `main` (or the current
   branch) in yellow at the far left.
4. After modifying, staging, or adding an untracked file, the statusline
   shows `*main`.
5. Outside a git repo, or on a detached HEAD, the widget is absent and the
   existing statusline layout is unchanged.
6. The tmux status bar is unchanged on all platforms.
