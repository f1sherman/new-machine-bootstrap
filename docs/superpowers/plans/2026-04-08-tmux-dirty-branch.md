# tmux Dirty-Branch Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show `(*branch)` inside tmux's `status-left` when the pane's current directory is a dirty git worktree; keep the current `(branch)` rendering for clean worktrees and render nothing outside git / on detached HEAD.

**Architecture:** A small bash helper script reads a path from `$1`, runs git, and prints `(*<branch>) ` / `(<branch>) ` / empty. Both `tmux.conf` files (macOS template + Linux copy) replace their existing inline `status-left` shell pipeline with a single call into the helper. Ansible installs the helper alongside the other `tmux-*` scripts.

**Tech Stack:** bash, git, Ansible, tmux, Jinja2 (for the macOS tmux.conf template).

**Spec:** `docs/superpowers/specs/2026-04-08-tmux-dirty-branch-design.md`

**Phases and human-review gates:**

1. **Phase 1** — Helper script built with red/green TDD and a self-contained test harness. Human review gate before moving on.
2. **Phase 2** — Ansible installs the helper script to `~/.local/bin/`. Red/green verification on provisioning. Human review gate.
3. **Phase 3** — Both `tmux.conf` files updated to call the helper. `bin/provision` applies the change, the installed `~/.tmux.conf` is sanity-checked with `tmux source-file`, and the helper's end-to-end behaviour is verified from the command line. Human review gate.

---

## Phase 1 — Helper script with TDD

### Task 1: Test harness for `tmux-git-branch`

**Files:**
- Create: `roles/common/files/bin/tmux-git-branch.test`

The harness is a plain bash script that:
- creates isolated git repos under a tmp dir (cleaned up on exit),
- invokes `tmux-git-branch` with various path arguments,
- asserts the captured stdout (including trailing spaces where applicable),
- exits non-zero on any failure.

No bats/shunit dependency.

- [ ] **Step 1.1: Create the test harness file**

Create `roles/common/files/bin/tmux-git-branch.test` with exactly this content:

```bash
#!/usr/bin/env bash
# Test harness for tmux-git-branch. Creates isolated git repos and invokes
# the script with various path arguments, asserting stdout (trailing spaces
# included).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-git-branch"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

GIT_AUTHOR_NAME=test
GIT_AUTHOR_EMAIL=test@example.com
GIT_COMMITTER_NAME=test
GIT_COMMITTER_EMAIL=test@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

pass=0
fail=0

# run_case takes the expected value via stdin (via "$expected") so trailing
# whitespace is preserved across comparisons. bash command substitution
# $(...) strips trailing newlines but preserves trailing spaces.
run_case() {
  local name="$1" expected="$2"
  shift 2
  local actual
  actual=$("$SCRIPT" "$@")
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      args     :'
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
    printf '      expected : %q\n' "$expected"
    printf '      actual   : %q\n' "$actual"
  fi
}

# --- Case 1: missing argument ---
run_case "missing argument" ""

# --- Case 2: empty argument ---
run_case "empty argument" "" ""

# --- Case 3: nonexistent directory ---
run_case "nonexistent directory" "" "/nonexistent/xyzzy-$$"

# --- Case 4: non-git directory ---
non_repo="$TMPROOT/not-a-repo"
mkdir -p "$non_repo"
run_case "non-git directory" "" "$non_repo"

# --- Case 5: fresh repo on main, clean ---
clean="$TMPROOT/clean"
git init -qb main "$clean"
git -C "$clean" commit -q --allow-empty -m init
run_case "clean repo on main" "(main) " "$clean"

# --- Case 6: modified tracked file ---
modified="$TMPROOT/modified"
git init -qb main "$modified"
echo a > "$modified/f"
git -C "$modified" add f
git -C "$modified" commit -q -m init
echo b > "$modified/f"
run_case "modified tracked file" "(*main) " "$modified"

# --- Case 7: staged change ---
staged="$TMPROOT/staged"
git init -qb main "$staged"
echo a > "$staged/f"
git -C "$staged" add f
git -C "$staged" commit -q -m init
echo b > "$staged/f"
git -C "$staged" add f
run_case "staged change" "(*main) " "$staged"

# --- Case 8: untracked file only ---
untracked="$TMPROOT/untracked"
git init -qb main "$untracked"
git -C "$untracked" commit -q --allow-empty -m init
echo x > "$untracked/newfile"
run_case "untracked file only" "(*main) " "$untracked"

# --- Case 9: detached HEAD ---
detached="$TMPROOT/detached"
git init -qb main "$detached"
git -C "$detached" commit -q --allow-empty -m first
git -C "$detached" commit -q --allow-empty -m second
sha=$(git -C "$detached" rev-parse HEAD~1)
git -C "$detached" checkout -q "$sha"
run_case "detached HEAD" "" "$detached"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 1.2: Make the test harness executable**

Run:
```bash
chmod +x roles/common/files/bin/tmux-git-branch.test
```

- [ ] **Step 1.3: Run the harness to confirm RED**

Run:
```bash
roles/common/files/bin/tmux-git-branch.test
```

Expected: the harness exits non-zero with `ERROR: <path>/tmux-git-branch is not executable (or does not exist)`. This is the red state — the helper script doesn't exist yet.

- [ ] **Step 1.4: Commit the test harness**

Run:
```bash
git add roles/common/files/bin/tmux-git-branch.test
git -c commit.gpgsign=false commit -m "Add tmux-git-branch test harness (red)"
```

### Task 2: Implement `tmux-git-branch`

**Files:**
- Create: `roles/common/files/bin/tmux-git-branch`

- [ ] **Step 2.1: Write the helper script**

Create `roles/common/files/bin/tmux-git-branch` with exactly this content:

```bash
#!/usr/bin/env bash
# Print `(*<branch>) ` if the given path is inside a dirty git worktree,
# `(<branch>) ` if clean, or empty otherwise. First argument is the path
# to inspect (in practice, tmux's #{pane_current_path}). Always exits 0
# so broken invocations never surface as error text in the tmux status
# bar.
set -u

dir="${1:-}"

if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  exit 0
fi

cd "$dir" 2>/dev/null || exit 0

if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  exit 0
fi

branch=$(git branch --show-current 2>/dev/null)
if [ -z "$branch" ]; then
  exit 0
fi

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  printf '(*%s) ' "$branch"
else
  printf '(%s) ' "$branch"
fi
```

- [ ] **Step 2.2: Make the script executable**

Run:
```bash
chmod +x roles/common/files/bin/tmux-git-branch
```

- [ ] **Step 2.3: Run the harness to confirm GREEN**

Run:
```bash
roles/common/files/bin/tmux-git-branch.test
```

Expected output ends with `9 passed, 0 failed` and exits 0.

If any case fails, read the diff, fix the script, and re-run until all nine pass.

- [ ] **Step 2.4: Self-review**

Look at the script and ask:
- Does every early-exit path exit 0? (Yes: every guarded return is `exit 0`; the final `printf` falls through to exit 0.)
- Are all `git` invocations guarded with `2>/dev/null`? (Yes.)
- Does `set -u` trip on any code path? (No — `dir` uses `${1:-}`, `branch` is unconditionally assigned before reference.)
- Is there any shell injection risk from `$1`? (No — we only pass `$dir` to `cd` and quote it; we never pass it to `eval` or `bash -c`.)
- Does the script use `printf` (not `echo`) for the output, so format is deterministic? (Yes.)
- Does the output include the trailing space required by the spec? (Yes — both `'(*%s) '` and `'(%s) '` end with a literal space.)

If anything above is wrong, fix it and re-run the harness (step 2.3) before continuing.

- [ ] **Step 2.5: Commit**

Run:
```bash
git add roles/common/files/bin/tmux-git-branch
git -c commit.gpgsign=false commit -m "Add tmux-git-branch helper script (green)"
```

### Phase 1 Human Review Gate

**Stop here.** Present a summary to the user:
- Files created: `roles/common/files/bin/tmux-git-branch`, `roles/common/files/bin/tmux-git-branch.test`
- Test results: 9 passed, 0 failed
- Self-review findings: (list anything caught, even if already fixed)

Wait for user approval before starting Phase 2.

---

## Phase 2 — Ansible install task

### Task 3: Install the helper script via Ansible

**Files:**
- Modify: `roles/common/tasks/main.yml` (insert a new task between `Install tmux-host-tag script` at line 200 and `Install tmux-window-name script` at line 207)

- [ ] **Step 3.1: RED — confirm script is NOT installed yet**

Run:
```bash
ls -l ~/.local/bin/tmux-git-branch 2>&1 | head -1
```

Expected: `ls: /Users/brian/.local/bin/tmux-git-branch: No such file or directory` (or an analogous "not found" message). If the file already exists — for example because it was manually copied during Phase 1 — remove it first with `rm ~/.local/bin/tmux-git-branch` so the red state is real.

- [ ] **Step 3.2: Add the install task**

In `roles/common/tasks/main.yml`, find the existing task at lines 200–205:

```yaml
- name: Install tmux-host-tag script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-host-tag'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-host-tag'
    mode: 0755
```

Insert a new task immediately after it (before the `Install tmux-window-name script` task at line 207):

```yaml
- name: Install tmux-git-branch script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-git-branch'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-git-branch'
    mode: 0755
```

- [ ] **Step 3.3: Dry-run the playbook**

Run:
```bash
bin/provision --check --diff
```

Expected: no errors. The diff should show the `Install tmux-git-branch script` task as `changed`. The pre-existing `Install gsd-browser skill for AI agents` failure on `/private/var/db/DifferentialPrivacy` may appear in `--check` mode — it is not introduced by this branch and should be ignored.

- [ ] **Step 3.4: Provision for real**

Run:
```bash
bin/provision
```

Expected: playbook completes successfully. The `Install tmux-git-branch script` task reports `changed`.

- [ ] **Step 3.5: GREEN — assert script is installed and executable**

Run:
```bash
ls -l ~/.local/bin/tmux-git-branch
```

Expected: the file exists and its mode includes `x` (e.g., `-rwxr-xr-x`).

Then run an end-to-end check against the installed script using the current worktree:
```bash
~/.local/bin/tmux-git-branch "$PWD"
```

Expected: `(feature/tmux-dirty-branch) ` (with trailing space) if the worktree is clean, or `(*feature/tmux-dirty-branch) ` if it has uncommitted changes.

- [ ] **Step 3.6: Self-review the Ansible change**

Look at the diff of `roles/common/tasks/main.yml` and ask:
- Does the new task exactly match the indentation and quoting style of the neighbouring tasks (`tmux-host-tag`, `tmux-window-name`)?
- Are `dest:` and `src:` correctly paired (not swapped)?
- Is `mode: 0755` (unquoted integer), matching the other bin tasks?
- Is `backup: yes` present, matching the pattern?
- Is the task inserted in the right position (between `tmux-host-tag` and `tmux-window-name`), keeping the tmux helpers contiguous?

If anything is off, fix it, re-run `bin/provision --check --diff` to verify the playbook still parses, and re-run the end-to-end check.

- [ ] **Step 3.7: Commit**

Run:
```bash
git add roles/common/tasks/main.yml
git -c commit.gpgsign=false commit -m "Install tmux-git-branch via Ansible"
```

### Phase 2 Human Review Gate

**Stop here.** Present a summary to the user:
- File modified: `roles/common/tasks/main.yml` (one task added)
- Provisioning result: success
- End-to-end check result: `<actual output from step 3.5>`
- Self-review findings

Wait for user approval before starting Phase 3.

---

## Phase 3 — tmux.conf edits

### Task 4: Replace the inline status-left shell with the helper script in both tmux configs

**Files:**
- Modify: `roles/linux/files/dotfiles/tmux.conf` (line 53)
- Modify: `roles/macos/templates/dotfiles/tmux.conf` (line 55)

- [ ] **Step 4.1: RED — confirm the new `status-left` is NOT yet in either installed config**

Run:
```bash
grep -c "tmux-git-branch" ~/.tmux.conf
```

Expected: `0` (the installed tmux.conf still uses the inline shell fragment).

Also verify both source files still have the old fragment:
```bash
grep -l "branch --show-current" roles/linux/files/dotfiles/tmux.conf roles/macos/templates/dotfiles/tmux.conf
```

Expected: both filenames printed — neither source file has been edited yet.

- [ ] **Step 4.2: Edit the Linux tmux.conf**

Open `roles/linux/files/dotfiles/tmux.conf`. Line 53 currently reads:

```
set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

Replace the whole line with:

```
set -g status-left '#[fg=yellow]#($HOME/.local/bin/tmux-git-branch "#{pane_current_path}")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

Leave `status-left-length 80` on line 52, `status-right` on line 54, and every other line unchanged.

- [ ] **Step 4.3: Edit the macOS tmux.conf template**

Open `roles/macos/templates/dotfiles/tmux.conf`. Line 55 currently reads:

```
set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

Replace the whole line with the same content as the Linux version:

```
set -g status-left '#[fg=yellow]#($HOME/.local/bin/tmux-git-branch "#{pane_current_path}")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

Leave the Jinja2 `{% raw %}` / `{% endraw %}` blocks elsewhere in the file untouched. The replaced line is outside any raw block, and the new content contains no Jinja2 meta-characters, so no raw wrapping is needed.

- [ ] **Step 4.4: Verify both source files are now identical on the relevant line**

Run:
```bash
grep -n "tmux-git-branch" roles/linux/files/dotfiles/tmux.conf roles/macos/templates/dotfiles/tmux.conf
```

Expected: each file prints exactly one line with the new `status-left` definition, and the content after the filename is byte-identical between the two files.

Also verify the old inline shell is gone:
```bash
grep -c "branch --show-current" roles/linux/files/dotfiles/tmux.conf roles/macos/templates/dotfiles/tmux.conf
```

Expected: both files print `0`.

- [ ] **Step 4.5: Dry-run the playbook**

Run:
```bash
bin/provision --check --diff
```

Expected: no errors. On macOS, the `Template dotfiles tmux.conf` task (from the macOS role) reports `changed`, and the diff shows only the `status-left` line. On Linux you'd expect the analogous `Copy tmux.conf` task to report `changed`; on macOS the Linux task is skipped via `when:` guards, so it will show `skipped` or simply not run.

- [ ] **Step 4.6: Provision for real**

Run:
```bash
bin/provision
```

Expected: playbook completes successfully. The tmux.conf install task (`Template dotfiles tmux.conf` on macOS, or the `copy` task in the linux role on Debian hosts) reports `changed`.

- [ ] **Step 4.7: GREEN — confirm the installed config has the new line**

Run:
```bash
grep -n "tmux-git-branch" ~/.tmux.conf
```

Expected: exactly one line printed, matching the new `status-left` definition.

Also verify the old inline shell is no longer there:
```bash
grep -c "branch --show-current" ~/.tmux.conf
```

Expected: `0`.

- [ ] **Step 4.8: Sanity-check the config with an isolated tmux server**

This catches any syntax errors in the new `status-left` without touching any running tmux session. Use a custom socket name (`-L cfg-check`) so this doesn't affect any existing tmux server, and `-f /dev/null` to suppress loading the default config on startup, then explicitly `source-file` the installed config and kill the temp server.

Run:
```bash
tmux -L cfg-check -f /dev/null start-server \; source-file ~/.tmux.conf \; kill-server 2>&1
echo "exit: $?"
```

Expected: no error messages, and `exit: 0`. If you see errors (e.g., `unknown command`, `bad format`, `unmatched quote`), the config has a syntax error — stop and diagnose before continuing. Note: this check only catches static tmux/config syntax errors. Shell errors inside `#(...)` interpolations won't fire until the status bar actually refreshes, and are caught by the manual verification in the human review gate.

- [ ] **Step 4.9: End-to-end live check of the installed helper**

Run:
```bash
~/.local/bin/tmux-git-branch "$PWD"
```

Expected: `(feature/tmux-dirty-branch) ` or `(*feature/tmux-dirty-branch) `. (The helper was already verified in Phase 2 — this just confirms it still works after the config change, which it should because Phase 3 did not touch the helper.)

Also run it against a non-git directory to verify the empty case:
```bash
~/.local/bin/tmux-git-branch /tmp
```

Expected: empty output (exit 0).

- [ ] **Step 4.10: Self-review the tmux.conf edits**

Look at the diffs of both tmux.conf files and ask:
- Is the replaced `status-left` line byte-identical between the macOS template and the Linux copy?
- Are the `#[fg=yellow]`, `#[fg=cyan]#{b:pane_current_path}`, and `#[fg=white]#($HOME/.local/bin/tmux-host-tag)` segments all still present and in the same order?
- Is the outer single-quote wrapping intact?
- Is there any stray whitespace (leading, trailing, between segments) that differs from the original?
- Does the new line contain zero Jinja2 meta-characters (no `{{`, `}}`, `{%`, `%}`)?

If anything is off, fix it and re-run steps 4.7, 4.8, and 4.9.

- [ ] **Step 4.11: Commit**

Run:
```bash
git add roles/linux/files/dotfiles/tmux.conf roles/macos/templates/dotfiles/tmux.conf
git -c commit.gpgsign=false commit -m "Use tmux-git-branch helper in status-left"
```

### Phase 3 Human Review Gate

**Stop here.** Present a summary to the user:
- Files modified: `roles/linux/files/dotfiles/tmux.conf`, `roles/macos/templates/dotfiles/tmux.conf`
- Provisioning result: success
- Installed `~/.tmux.conf` grep result: shows the new `tmux-git-branch` line and no longer contains `branch --show-current`
- `tmux source-file ~/.tmux.conf` result: no errors
- End-to-end helper output: `<actual output>`
- Self-review findings

Tell the user they can visually verify the change in their running tmux sessions by running `tmux source-file ~/.tmux.conf` in any existing session (or starting a new one) and then waiting up to 5 seconds for the status bar to refresh. In a dirty git repo pane it should show `(*branch)` in yellow; in a clean repo, `(branch)`; outside git, nothing.

Wait for user approval before considering the work complete.

---

## Success Criteria (recap from spec)

1. `bin/provision` installs the new script, updates both tmux configs, and leaves the rest of the system unchanged.
2. `roles/common/files/bin/tmux-git-branch.test` passes all nine cases.
3. In a running tmux pane whose cwd is a clean git repo, the status-left shows `(branch) ` in yellow.
4. In a dirty repo, it shows `(*branch) ` in yellow.
5. Outside a git repo or on detached HEAD, the branch segment is absent and the rest of the status bar (directory, host tag) renders normally.
6. The Claude Code `cc-git-branch-dirty` widget continues to behave unchanged.
