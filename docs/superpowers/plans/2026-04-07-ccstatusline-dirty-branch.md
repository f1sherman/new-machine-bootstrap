# ccstatusline Dirty-Branch Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a leading `*` next to the current git branch name in the Claude Code statusline when the working tree is dirty (modified, staged, or untracked changes).

**Architecture:** A small bash helper script reads the Claude Code status JSON from stdin, extracts `cwd`, and prints `*<branch>`, `<branch>`, or empty. A new ccstatusline `custom-command` widget invokes the script. Ansible installs the script to `~/.local/bin/` alongside the existing helpers.

**Tech Stack:** bash, jq, git, Ansible, ccstatusline (via `custom-command` widget type).

**Spec:** `docs/superpowers/specs/2026-04-07-ccstatusline-dirty-branch-design.md`

**Phases and human-review gates:**

1. **Phase 1** — Helper script built with red/green TDD and a self-contained test harness. Human review gate before moving on.
2. **Phase 2** — Ansible installs the helper script to `~/.local/bin/`. Red/green verification on provisioning. Human review gate.
3. **Phase 3** — ccstatusline widget added to the settings template and verified in a live Claude Code render. Human review gate.

---

## Phase 1 — Helper script with TDD

### Task 1: Test harness for `cc-git-branch-dirty`

**Files:**
- Create: `roles/common/files/bin/cc-git-branch-dirty.test`

The harness is a plain bash script that:
- creates isolated git repos under a tmp dir (cleaned up on exit),
- pipes synthesized Claude JSON to `cc-git-branch-dirty`,
- diffs the output against expected values,
- exits non-zero on any failure.

No bats/shunit dependency.

- [ ] **Step 1.1: Create the test harness file**

Create `roles/common/files/bin/cc-git-branch-dirty.test` with exactly this content:

```bash
#!/usr/bin/env bash
# Test harness for cc-git-branch-dirty. Creates isolated git repos and
# pipes synthesized Claude status JSON to the script, asserting output.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/cc-git-branch-dirty"

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

run_case() {
  local name="$1" input="$2" expected="$3"
  local actual
  actual=$(printf '%s' "$input" | "$SCRIPT")
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      input    : %s\n' "$input"
    printf '      expected : %q\n' "$expected"
    printf '      actual   : %q\n' "$actual"
  fi
}

# --- Case 1: cwd is not inside a git worktree ---
non_repo="$TMPROOT/not-a-repo"
mkdir -p "$non_repo"
run_case "not in a git repo" "{\"cwd\":\"$non_repo\"}" ""

# --- Case 2: fresh repo on main, clean ---
clean="$TMPROOT/clean"
git init -qb main "$clean"
git -C "$clean" commit -q --allow-empty -m init
run_case "clean repo on main" "{\"cwd\":\"$clean\"}" "main"

# --- Case 3: modified tracked file ---
modified="$TMPROOT/modified"
git init -qb main "$modified"
echo a > "$modified/f"
git -C "$modified" add f
git -C "$modified" commit -q -m init
echo b > "$modified/f"
run_case "modified tracked file" "{\"cwd\":\"$modified\"}" "*main"

# --- Case 4: staged change (modified then added) ---
staged="$TMPROOT/staged"
git init -qb main "$staged"
echo a > "$staged/f"
git -C "$staged" add f
git -C "$staged" commit -q -m init
echo b > "$staged/f"
git -C "$staged" add f
run_case "staged change" "{\"cwd\":\"$staged\"}" "*main"

# --- Case 5: untracked file only ---
untracked="$TMPROOT/untracked"
git init -qb main "$untracked"
git -C "$untracked" commit -q --allow-empty -m init
echo x > "$untracked/newfile"
run_case "untracked file only" "{\"cwd\":\"$untracked\"}" "*main"

# --- Case 6: detached HEAD ---
detached="$TMPROOT/detached"
git init -qb main "$detached"
git -C "$detached" commit -q --allow-empty -m first
git -C "$detached" commit -q --allow-empty -m second
sha=$(git -C "$detached" rev-parse HEAD~1)
git -C "$detached" checkout -q "$sha"
run_case "detached HEAD" "{\"cwd\":\"$detached\"}" ""

# --- Case 7: JSON has no cwd or workspace.current_dir ---
run_case "empty JSON object" "{}" ""

# --- Case 8: cwd points at a nonexistent directory ---
run_case "nonexistent cwd" "{\"cwd\":\"/nonexistent/xyzzy-$$\"}" ""

# --- Case 9: workspace.current_dir fallback when cwd is absent ---
fallback="$TMPROOT/fallback"
git init -qb main "$fallback"
git -C "$fallback" commit -q --allow-empty -m init
run_case "workspace.current_dir fallback" \
  "{\"workspace\":{\"current_dir\":\"$fallback\"}}" "main"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 1.2: Make the test harness executable**

Run:
```bash
chmod +x roles/common/files/bin/cc-git-branch-dirty.test
```

- [ ] **Step 1.3: Run the harness to confirm RED**

Run:
```bash
roles/common/files/bin/cc-git-branch-dirty.test
```

Expected: the harness exits non-zero with `ERROR: <path>/cc-git-branch-dirty is not executable (or does not exist)`. This is the red state — the helper script doesn't exist yet.

- [ ] **Step 1.4: Commit the test harness**

Run:
```bash
git add roles/common/files/bin/cc-git-branch-dirty.test
git -c commit.gpgsign=false commit -m "Add cc-git-branch-dirty test harness (red)"
```

### Task 2: Implement `cc-git-branch-dirty`

**Files:**
- Create: `roles/common/files/bin/cc-git-branch-dirty`

- [ ] **Step 2.1: Write the helper script**

Create `roles/common/files/bin/cc-git-branch-dirty` with exactly this content:

```bash
#!/usr/bin/env bash
# Print `*<branch>` if the Claude Code cwd is inside a dirty git worktree,
# `<branch>` if clean, or empty otherwise. Stdin is Claude Code's status
# JSON. Always exits 0 so broken invocations never surface as error text
# in the statusline.
set -u

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)

if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
  exit 0
fi

cd "$cwd" 2>/dev/null || exit 0

if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  exit 0
fi

branch=$(git branch --show-current 2>/dev/null)
if [ -z "$branch" ]; then
  exit 0
fi

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  printf '*%s\n' "$branch"
else
  printf '%s\n' "$branch"
fi
```

- [ ] **Step 2.2: Make the script executable**

Run:
```bash
chmod +x roles/common/files/bin/cc-git-branch-dirty
```

- [ ] **Step 2.3: Run the harness to confirm GREEN**

Run:
```bash
roles/common/files/bin/cc-git-branch-dirty.test
```

Expected output ends with `9 passed, 0 failed` and exits 0.

If any case fails, read the diff, fix the script, and re-run until all nine pass.

- [ ] **Step 2.4: Self-review**

Look at the script and ask:
- Does every early-exit path exit 0? (Yes: `exit 0` on every branch; the final `printf` falls through to exit 0.)
- Are all `git` and `jq` invocations guarded with `2>/dev/null`? (Yes.)
- Does `set -u` trip on any code path? (No — `input`, `cwd`, and `branch` are all assigned before reference.)
- Is there any shell injection risk from the JSON content? (No — we only pass `$cwd` to `cd` and never to `eval` or `bash -c`.)
- Does the script handle both `.cwd` and `.workspace.current_dir`? (Yes, via `//` in jq.)

If anything above is wrong, fix it and re-run the harness (step 2.3) before continuing.

- [ ] **Step 2.5: Commit**

Run:
```bash
git add roles/common/files/bin/cc-git-branch-dirty
git -c commit.gpgsign=false commit -m "Add cc-git-branch-dirty helper script (green)"
```

### Phase 1 Human Review Gate

**Stop here.** Present a summary to the user:
- Files created: `roles/common/files/bin/cc-git-branch-dirty`, `roles/common/files/bin/cc-git-branch-dirty.test`
- Test results: 9 passed, 0 failed
- Self-review findings: (list anything you caught, even if already fixed)

Wait for user approval before starting Phase 2.

---

## Phase 2 — Ansible install task

### Task 3: Install the helper script via Ansible

**Files:**
- Modify: `roles/common/tasks/main.yml` (insert after line 226, the `Install claude-trust-directory script` task)

- [ ] **Step 3.1: RED — confirm script is NOT installed yet**

Run:
```bash
ls -l ~/.local/bin/cc-git-branch-dirty 2>&1 | head -1
```

Expected: `ls: /Users/brian/.local/bin/cc-git-branch-dirty: No such file or directory` (or an analogous "not found" message). If the file already exists — for example because you manually copied it during Phase 1 — remove it first with `rm ~/.local/bin/cc-git-branch-dirty` so the red state is real.

- [ ] **Step 3.2: Add the install task**

In `roles/common/tasks/main.yml`, find the existing task at lines 221–226:

```yaml
- name: Install claude-trust-directory script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/claude-trust-directory'
    src: '{{ playbook_dir }}/roles/common/files/bin/claude-trust-directory'
    mode: 0755
```

Insert a new task immediately after it (before the `Create ~/.claude directory` task):

```yaml
- name: Install cc-git-branch-dirty script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/cc-git-branch-dirty'
    src: '{{ playbook_dir }}/roles/common/files/bin/cc-git-branch-dirty'
    mode: 0755
```

- [ ] **Step 3.3: Dry-run the playbook**

Run:
```bash
bin/provision --check --diff
```

Expected: no errors. The diff should show the `Install cc-git-branch-dirty script` task as `changed` (or `ok` if the file already happens to match). No other tasks should be affected by this change.

- [ ] **Step 3.4: Provision for real**

Run:
```bash
bin/provision
```

Expected: playbook completes successfully. The `Install cc-git-branch-dirty script` task reports `changed`.

- [ ] **Step 3.5: GREEN — assert script is installed and executable**

Run:
```bash
ls -l ~/.local/bin/cc-git-branch-dirty
```

Expected: the file exists and its mode includes `x` (e.g., `-rwxr-xr-x`).

Then run an end-to-end check against the installed script using the current worktree as a dirty repo:
```bash
printf '{"cwd":"%s"}' "$PWD" | ~/.local/bin/cc-git-branch-dirty
```

Expected: `*feature/statusline-dirty-branch` (the leading `*` because the worktree has uncommitted changes from this implementation session, or `feature/statusline-dirty-branch` if you are temporarily clean).

If the output is empty, check that `jq` is on PATH (`command -v jq`) and that `$PWD` is inside the worktree.

- [ ] **Step 3.6: Self-review the Ansible change**

Look at the diff of `roles/common/tasks/main.yml` and ask:
- Does the new task exactly match the indentation and quoting style of the neighbouring tasks?
- Are `dest:` and `src:` correctly paired (not swapped)?
- Is `mode: 0755` (unquoted integer), matching the other bin tasks?
- Is `backup: yes` present, matching the pattern?

If anything is off, fix it, re-run `bin/provision --check --diff` to verify the playbook still parses, and re-run the end-to-end check.

- [ ] **Step 3.7: Commit**

Run:
```bash
git add roles/common/tasks/main.yml
git -c commit.gpgsign=false commit -m "Install cc-git-branch-dirty via Ansible"
```

### Phase 2 Human Review Gate

**Stop here.** Present a summary to the user:
- File modified: `roles/common/tasks/main.yml` (one task added)
- Provisioning result: success
- End-to-end check result: `<actual output from step 3.5>`
- Self-review findings

Wait for user approval before starting Phase 3.

---

## Phase 3 — ccstatusline widget

### Task 4: Add `custom-command` widget to the ccstatusline config

**Files:**
- Modify: `roles/common/files/config/ccstatusline/settings.json`

- [ ] **Step 4.1: RED — confirm widget is NOT in the installed config**

Run:
```bash
jq '[.lines[0][].id] | any(. == "git-branch-dirty")' ~/.config/ccstatusline/settings.json
```

Expected: `false`.

- [ ] **Step 4.2: Edit the source settings template**

Open `roles/common/files/config/ccstatusline/settings.json`. The current `lines[0]` array contains two entries with ids `"1"` (model) and `"2"` (context percentage). Prepend a new entry so the array becomes:

```json
"lines": [
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
      "metadata": {
        "inverse": "true"
      }
    }
  ],
  [],
  []
],
```

Do not touch any other field (`flexMode`, `powerline`, etc.).

- [ ] **Step 4.3: Validate the source JSON**

Run:
```bash
jq '.lines[0] | map(.id)' roles/common/files/config/ccstatusline/settings.json
```

Expected: `["git-branch-dirty", "1", "2"]`.

- [ ] **Step 4.4: Provision to copy the updated settings**

Run:
```bash
bin/provision
```

Expected: playbook completes successfully. The `Install ccstatusline widget configuration` task reports `changed`.

- [ ] **Step 4.5: GREEN — assert widget IS in the installed config**

Run:
```bash
jq '[.lines[0][].id] | any(. == "git-branch-dirty")' ~/.config/ccstatusline/settings.json
```

Expected: `true`.

Also run:
```bash
jq '.lines[0][0]' ~/.config/ccstatusline/settings.json
```

Expected output (formatting may differ):
```json
{
  "id": "git-branch-dirty",
  "type": "custom-command",
  "color": "yellow",
  "commandPath": "$HOME/.local/bin/cc-git-branch-dirty"
}
```

- [ ] **Step 4.6: Live render — dirty repo**

Run ccstatusline directly with a synthesized Claude status JSON, pointing at the current worktree (which is dirty from this implementation work):

```bash
printf '{"hook_event_name":"Status","cwd":"%s","model":{"id":"claude-opus-4-6"},"workspace":{"current_dir":"%s","project_dir":"%s"}}' "$PWD" "$PWD" "$PWD" \
  | npx -y ccstatusline@2.0.21
```

Expected: the rendered statusline includes `*feature/statusline-dirty-branch` at the far left in yellow, followed by the model name and context percentage.

- [ ] **Step 4.7: Live render — clean repo**

Pick any clean git repository on disk (or temporarily stash changes here). For example, run:

```bash
clean=$(mktemp -d)
git init -qb main "$clean"
git -C "$clean" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf '{"hook_event_name":"Status","cwd":"%s","model":{"id":"claude-opus-4-6"}}' "$clean" \
  | npx -y ccstatusline@2.0.21
rm -rf "$clean"
```

Expected: the rendered statusline shows `main` (no leading asterisk) in yellow at the far left.

- [ ] **Step 4.8: Live render — non-git directory**

Run:
```bash
printf '{"hook_event_name":"Status","cwd":"/tmp","model":{"id":"claude-opus-4-6"}}' \
  | npx -y ccstatusline@2.0.21
```

Expected: the rendered statusline contains the model name and context percentage but no branch widget and no powerline separator in its place.

- [ ] **Step 4.9: Self-review the settings change**

Look at the diff of `roles/common/files/config/ccstatusline/settings.json` and ask:
- Is the JSON still valid as a whole? (`jq . roles/common/files/config/ccstatusline/settings.json > /dev/null` exits 0.)
- Is the new widget first in `lines[0]` (so the asterisk lands at the leftmost position)?
- Are the existing widgets (model, context-percentage) untouched in field order and content?
- Is the `commandPath` an absolute path using `$HOME/...`?

If anything is off, fix it and re-run steps 4.5 and 4.6.

- [ ] **Step 4.10: Commit**

Run:
```bash
git add roles/common/files/config/ccstatusline/settings.json
git -c commit.gpgsign=false commit -m "Add dirty-branch widget to ccstatusline"
```

### Phase 3 Human Review Gate

**Stop here.** Present a summary to the user:
- File modified: `roles/common/files/config/ccstatusline/settings.json`
- Provisioning result: success
- Live render — dirty: `<output or description>`
- Live render — clean: `<output or description>`
- Live render — non-git: `<output or description>`
- Self-review findings

Wait for user approval before considering the work complete.

---

## Success Criteria (recap from spec)

1. `bin/provision` installs the helper script and the updated ccstatusline config on macOS.
2. `roles/common/files/bin/cc-git-branch-dirty.test` passes all nine cases.
3. Claude Code statusline shows `<branch>` in yellow in a clean repo.
4. Claude Code statusline shows `*<branch>` in yellow in a dirty repo.
5. Claude Code statusline widget is absent outside a git worktree or on detached HEAD.
6. tmux status bar is unchanged on all platforms.
