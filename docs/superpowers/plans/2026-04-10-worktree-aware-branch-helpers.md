# Worktree-Aware Branch Helpers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `b` jump into linked worktrees and make `db` delete branches safely when linked worktrees are involved.

**Architecture:** Keep branch/worktree discovery in shared bin scripts under `roles/common/files/bin/`. `git-switch-branch` becomes a selector that returns `checkout` or `cd`, while a new `git-delete-branch` owns safe deletion for ordinary branches and linked worktrees. Shell functions stay thin wrappers: `b` parses helper output and updates tmux pane state after `cd`; `db` delegates to the delete helper.

**Tech Stack:** Bash, zsh, Git worktree porcelain output, `fzf`, Ansible `copy` tasks, repo-local shell test harnesses.

---

## File Structure

- `roles/common/files/bin/git-switch-branch`
  Responsibility: enumerate local branches, detect linked worktrees, show compact markers, and print `checkout<TAB>branch` or `cd<TAB>path`.
- `roles/common/files/bin/git-switch-branch.test`
  Responsibility: TDD harness for the switch helper, including marker visibility and `cd` vs `checkout` action output.
- `roles/common/files/bin/git-delete-branch`
  Responsibility: enumerate deletable branches, detect linked worktrees, refuse dirty removals, remove clean linked worktrees, and delete the selected branch.
- `roles/common/files/bin/git-delete-branch.test`
  Responsibility: TDD harness for delete behavior, including ordinary deletion, clean linked worktree removal, and dirty linked worktree refusal.
- `roles/common/templates/dotfiles/zshrc`
  Responsibility: keep `b` and `db` as thin wrappers over the shared helpers and call `_worktree_sync_tmux_state` after `b` changes directory.
- `roles/macos/templates/dotfiles/bash_profile`
  Responsibility: keep `b` aligned with zsh behavior for action parsing and tmux state sync.
- `roles/common/tasks/main.yml`
  Responsibility: install `git-delete-branch` alongside `git-switch-branch`.

## Plan Metadata

- Date: `2026-04-10 19:51:12 CDT`
- Git Commit: `ac965808ad7711ce5bf607b691f391fa3e3ebff2`
- Branch: `fix/b-branch-switch-display`
- Repository: `fix-b-branch-switch-display`

### Task 1: Make `git-switch-branch` return worktree-aware actions

**Files:**
- Modify: `roles/common/files/bin/git-switch-branch`
- Modify: `roles/common/files/bin/git-switch-branch.test`
- Test: `roles/common/files/bin/git-switch-branch.test`

- [ ] **Step 1: Rewrite the test harness to expect helper actions instead of side-effect checkouts**

```bash
run_switch_case() {
  local name="$1" repo="$2" match="$3" expected_output="$4" expected_branch="$5" expected_row="$6"
  local bindir input_file rc actual_output actual_branch

  bindir="$(mktemp -d "$TMPROOT/fzfbin.XXXXXX")"
  input_file="$(mktemp "$TMPROOT/fzfinput.XXXXXX")"
  install_fake_fzf "$bindir"

  if actual_output=$(
    cd "$repo" &&
    PATH="$bindir:$PATH" \
    FAKE_FZF_MATCH="$match" \
    FAKE_FZF_INPUT_FILE="$input_file" \
    "$SCRIPT"
  ); then
    rc=0
  else
    rc=$?
  fi

  actual_branch="$(git -C "$repo" branch --show-current)"

  if [ "$rc" -eq 0 ] && \
     [ "$actual_output" = "$expected_output" ] && \
     [ "$actual_branch" = "$expected_branch" ] && \
     grep -Fqx "$expected_row" "$input_file"; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      expected output: %q\n' "$expected_output"
    printf '      actual output  : %q\n' "$actual_output"
    printf '      expected branch: %q\n' "$expected_branch"
    printf '      actual branch  : %q\n' "$actual_branch"
    printf '      expected row   : %q\n' "$expected_row"
    printf '      picker input:\n'
    sed 's/^/        /' "$input_file"
  fi
}

run_switch_case \
  "returns checkout action for available branch" \
  "$repo" \
  "  feature/available" \
  $'checkout\tfeature/available' \
  "main" \
  "feature/available\t \t\t  feature/available"

run_switch_case \
  "returns cd action for linked worktree branch" \
  "$repo" \
  "+ feature/in-other-worktree" \
  $'cd\t'"$TMPROOT/linked" \
  "main" \
  $'feature/in-other-worktree\t+\t'"$TMPROOT/linked"$'\t+ feature/in-other-worktree'
```

- [ ] **Step 2: Run the switch-helper test to verify it fails against the current helper**

Run: `bash roles/common/files/bin/git-switch-branch.test`
Expected: FAIL because the current helper still runs `git checkout` directly and does not print `checkout<TAB>...` or `cd<TAB>...`.

- [ ] **Step 3: Replace the helper implementation so it emits machine-readable actions**

```bash
#!/usr/bin/env bash
set -eu

current_root="$(git rev-parse --path-format=absolute --show-toplevel)"
current_branch="$(git branch --show-current 2>/dev/null || true)"

worktree_map="$(
  git worktree list --porcelain | awk -v current_root="$current_root" '
    $1 == "worktree" { worktree = substr($0, 10); next }
    $1 == "branch" {
      branch = substr($0, 8)
      if (branch ~ /^refs\/heads\// && worktree != current_root) {
        print substr(branch, 12) "\t" worktree
      }
    }
  '
)" || exit 1

branches="$(
  git for-each-ref --sort=refname --format='%(refname:short)' refs/heads | \
  while IFS= read -r branch; do
    marker=" "
    worktree_path=""
    if [ "$branch" = "$current_branch" ]; then
      marker="*"
    else
      worktree_path="$(printf '%s\n' "$worktree_map" | awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }')"
      [ -n "$worktree_path" ] && marker="+"
    fi
    printf '%s\t%s\t%s\t%s %s\n' "$branch" "$marker" "$worktree_path" "$marker" "$branch"
  done
)" || exit 1

[ -n "$branches" ] || exit 0

selection="$(
  printf '%s\n' "$branches" | fzf +m --delimiter=$'\t' --with-nth=4
)" || exit 0

IFS=$'\t' read -r branch marker worktree_path _display <<EOF
$selection
EOF

if [ -n "$worktree_path" ]; then
  printf 'cd\t%s\n' "$worktree_path"
else
  printf 'checkout\t%s\n' "$branch"
fi
```

- [ ] **Step 4: Run the switch-helper test to verify it passes**

Run: `bash roles/common/files/bin/git-switch-branch.test`
Expected: PASS with cases for ordinary branch selection, linked worktree selection, and visible `+` / `*` markers.

- [ ] **Step 5: Commit the switch-helper changes**

Run:

```bash
~/.codex/skills/committing-changes/commit.sh -m "Make git-switch-branch return worktree-aware actions" \
  roles/common/files/bin/git-switch-branch \
  roles/common/files/bin/git-switch-branch.test
```

Expected: one commit containing only the helper and its updated test.

### Task 2: Add a safe `git-delete-branch` helper for ordinary and linked worktrees

**Files:**
- Create: `roles/common/files/bin/git-delete-branch`
- Create: `roles/common/files/bin/git-delete-branch.test`
- Modify: `roles/common/tasks/main.yml`
- Test: `roles/common/files/bin/git-delete-branch.test`

- [ ] **Step 1: Create a failing delete-helper test harness**

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/git-delete-branch"

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

install_fake_fzf() {
  local bindir="$1"
  mkdir -p "$bindir"
  cat > "$bindir/fzf" <<'EOF'
#!/usr/bin/env bash
set -eu

input="$(cat)"
if [ -n "${FAKE_FZF_INPUT_FILE:-}" ]; then
  printf '%s' "$input" > "$FAKE_FZF_INPUT_FILE"
fi
selected="$(printf '%s\n' "$input" | grep -F -m 1 -- "${FAKE_FZF_MATCH:?}" || true)"
[ -n "$selected" ] || exit 1
printf '%s\n' "$selected"
EOF
  chmod +x "$bindir/fzf"
}

make_repo() {
  local dir="$1"
  git init -qb main "$dir"
  git -C "$dir" commit -q --allow-empty -m init
}

branch_state() {
  local repo="$1" branch="$2"
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    printf 'present\n'
  else
    printf 'absent\n'
  fi
}

worktree_state() {
  local path="$1"
  if [ -e "$path/.git" ]; then
    printf 'present\n'
  else
    printf 'absent\n'
  fi
}

run_delete_case() {
  local name="$1" repo="$2" match="$3" expected_rc="$4" expected_branch_state="$5" expected_worktree_state="$6" expected_message="$7" target_branch="$8" target_worktree="$9" expected_row="${10}"
  local bindir input_file output rc actual_branch_state actual_worktree_state

  bindir="$(mktemp -d "$TMPROOT/fzfbin.XXXXXX")"
  input_file="$(mktemp "$TMPROOT/fzfinput.XXXXXX")"
  install_fake_fzf "$bindir"

  if output=$(
    cd "$repo" &&
    PATH="$bindir:$PATH" \
    FAKE_FZF_MATCH="$match" \
    FAKE_FZF_INPUT_FILE="$input_file" \
    "$SCRIPT" 2>&1
  ); then
    rc=0
  else
    rc=$?
  fi

  actual_branch_state="$(branch_state "$repo" "$target_branch")"
  actual_worktree_state="$(worktree_state "$target_worktree")"

  if [ "$rc" -eq "$expected_rc" ] && \
     [ "$actual_branch_state" = "$expected_branch_state" ] && \
     [ "$actual_worktree_state" = "$expected_worktree_state" ] && \
     printf '%s' "$output" | grep -Fq "$expected_message" && \
     grep -Fqx "$expected_row" "$input_file" && \
     ! grep -Fq "* main" "$input_file"; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      output: %s\n' "$output"
    printf '      branch state: %s\n' "$actual_branch_state"
    printf '      worktree state: %s\n' "$actual_worktree_state"
    printf '      picker input:\n'
    sed 's/^/        /' "$input_file"
  fi
}

ordinary_repo="$TMPROOT/ordinary"
make_repo "$ordinary_repo"
git -C "$ordinary_repo" branch feature/free
run_delete_case \
  "deletes ordinary branch" \
  "$ordinary_repo" \
  "  feature/free" \
  0 \
  "absent" \
  "absent" \
  "Deleted branch feature/free" \
  "feature/free" \
  "$TMPROOT/no-worktree" \
  $'feature/free\t \t\t  feature/free'

clean_repo="$TMPROOT/clean"
clean_worktree="$TMPROOT/linked"
make_repo "$clean_repo"
git -C "$clean_repo" worktree add -q -b feature/linked "$clean_worktree"
run_delete_case \
  "removes clean linked worktree then deletes branch" \
  "$clean_repo" \
  "+ feature/linked" \
  0 \
  "absent" \
  "absent" \
  "Removed worktree $clean_worktree" \
  "feature/linked" \
  "$clean_worktree" \
  $'feature/linked\t+\t'"$clean_worktree"$'\t+ feature/linked'

dirty_repo="$TMPROOT/dirty"
dirty_worktree="$TMPROOT/dirty-linked"
make_repo "$dirty_repo"
git -C "$dirty_repo" worktree add -q -b feature/dirty "$dirty_worktree"
echo dirty > "$dirty_worktree/file.txt"
run_delete_case \
  "refuses dirty linked worktree deletion" \
  "$dirty_repo" \
  "+ feature/dirty" \
  1 \
  "present" \
  "present" \
  "$dirty_worktree" \
  "feature/dirty" \
  "$dirty_worktree" \
  $'feature/dirty\t+\t'"$dirty_worktree"$'\t+ feature/dirty'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the delete-helper test to verify it fails before implementation**

Run: `bash roles/common/files/bin/git-delete-branch.test`
Expected: FAIL with `ERROR: .../git-delete-branch is not executable (or does not exist)`.

- [ ] **Step 3: Implement the helper and install task**

Create `roles/common/files/bin/git-delete-branch` with:

```bash
#!/usr/bin/env bash
set -eu

current_root="$(git rev-parse --path-format=absolute --show-toplevel)"
current_branch="$(git branch --show-current 2>/dev/null || true)"

worktree_map="$(
  git worktree list --porcelain | awk -v current_root="$current_root" '
    $1 == "worktree" { worktree = substr($0, 10); next }
    $1 == "branch" {
      branch = substr($0, 8)
      if (branch ~ /^refs\/heads\// && worktree != current_root) {
        print substr(branch, 12) "\t" worktree
      }
    }
  '
)"

branches="$(
  git for-each-ref --sort=refname --format='%(refname:short)' refs/heads | \
  while IFS= read -r branch; do
    [ "$branch" = "$current_branch" ] && continue
    worktree_path="$(printf '%s\n' "$worktree_map" | awk -F '\t' -v branch="$branch" '$1 == branch { print $2; exit }')"
    marker=" "
    [ -n "$worktree_path" ] && marker="+"
    printf '%s\t%s\t%s\t%s %s\n' "$branch" "$marker" "$worktree_path" "$marker" "$branch"
  done
)" || exit 1

[ -n "$branches" ] || exit 0

selection="$(
  printf '%s\n' "$branches" | fzf +m --delimiter=$'\t' --with-nth=4
)" || exit 0

IFS=$'\t' read -r branch _marker worktree_path _display <<EOF
$selection
EOF

if [ -n "$worktree_path" ]; then
  if [ -n "$(git -C "$worktree_path" status --porcelain)" ]; then
    printf 'Refusing to delete %s: linked worktree is dirty at %s\n' "$branch" "$worktree_path" >&2
    exit 1
  fi
  git worktree remove "$worktree_path"
  printf 'Removed worktree %s\n' "$worktree_path"
fi

git branch -D "$branch"
```

Add this install task in `roles/common/tasks/main.yml` immediately after the existing `git-switch-branch` task:

```yaml
- name: Install git-delete-branch script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/git-delete-branch'
    src: '{{ playbook_dir }}/roles/common/files/bin/git-delete-branch'
    mode: 0755
```

- [ ] **Step 4: Run the delete-helper test to verify it passes**

Run: `bash roles/common/files/bin/git-delete-branch.test`
Expected: PASS for ordinary deletion, clean linked worktree removal, and dirty linked worktree refusal.

- [ ] **Step 5: Commit the delete-helper changes**

Run:

```bash
~/.codex/skills/committing-changes/commit.sh -m "Add safe linked-worktree branch deletion helper" \
  roles/common/files/bin/git-delete-branch \
  roles/common/files/bin/git-delete-branch.test \
  roles/common/tasks/main.yml
```

Expected: one commit containing the new helper, its test, and the install task.

### Task 3: Update shell wrappers to use the shared helpers correctly

**Files:**
- Modify: `roles/common/templates/dotfiles/zshrc`
- Modify: `roles/macos/templates/dotfiles/bash_profile`
- Test: `/tmp/branch-helper-shell-smoke.sh` (temporary verification script)

- [ ] **Step 1: Write a temporary shell smoke script that exercises `b` and `db` through the real wrapper code**

Create `/tmp/branch-helper-shell-smoke.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

repo="$TMPROOT/repo"
linked="$TMPROOT/linked"
dirty="$TMPROOT/dirty"
home="$TMPROOT/home"
bindir="$home/.local/bin"
mkdir -p "$bindir"

cp "$ROOT/roles/common/files/bin/git-switch-branch" "$bindir/git-switch-branch"
cp "$ROOT/roles/common/files/bin/git-delete-branch" "$bindir/git-delete-branch"
chmod +x "$bindir/git-switch-branch" "$bindir/git-delete-branch"

cat > "$bindir/fzf" <<'EOF'
#!/usr/bin/env bash
set -eu
input="$(cat)"
selected="$(printf '%s\n' "$input" | grep -F -m 1 -- "${FAKE_FZF_MATCH:?}" || true)"
[ -n "$selected" ] || exit 1
printf '%s\n' "$selected"
EOF
chmod +x "$bindir/fzf"

GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
git init -qb main "$repo"
GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
git -C "$repo" commit -q --allow-empty -m init
git -C "$repo" branch feature/free
git -C "$repo" worktree add -q -b feature/linked "$linked"
git -C "$repo" worktree add -q -b feature/dirty "$dirty"
echo dirty > "$dirty/file.txt"

cat > "$TMPROOT/run-zsh-smoke.zsh" <<EOF
_worktree_sync_tmux_state() { :; }
$(sed -n '/^alias b > \\/dev\\/null && unalias b$/, /^}/p' "$ROOT/roles/common/templates/dotfiles/zshrc")
$(sed -n '/^alias db > \\/dev\\/null && unalias db$/, /^}/p' "$ROOT/roles/common/templates/dotfiles/zshrc")
cd "$repo"
FAKE_FZF_MATCH="+ feature/linked"
b
pwd
cd "$repo"
FAKE_FZF_MATCH="  feature/free"
db
git branch --list feature/free
cd "$repo"
FAKE_FZF_MATCH="+ feature/dirty"
db
EOF

cat > "$TMPROOT/run-bash-smoke.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
_worktree_sync_tmux_state() { :; }
$(sed -n '/^b() {$/, /^}/p' "$ROOT/roles/macos/templates/dotfiles/bash_profile")
cd "$repo"
FAKE_FZF_MATCH="+ feature/linked"
b
pwd
EOF
chmod +x "$TMPROOT/run-bash-smoke.sh"

PATH="$bindir:$PATH" HOME="$home" zsh "$TMPROOT/run-zsh-smoke.zsh"
PATH="$bindir:$PATH" HOME="$home" bash "$TMPROOT/run-bash-smoke.sh"
```

- [ ] **Step 2: Run the temporary shell smoke script to verify it fails before the wrapper edits**

Run: `bash /tmp/branch-helper-shell-smoke.sh`
Expected:
- the zsh portion fails because `b` still treats `git-switch-branch` as a side-effect helper and `db` still parses `git branch` output inline
- the bash portion fails because `b` still ignores the `cd<TAB>...` action output

- [ ] **Step 3: Update the shell wrappers**

Replace the zsh `b` / `db` functions in `roles/common/templates/dotfiles/zshrc` with:

```bash
alias b > /dev/null && unalias b
function b() {
  local selection action value
  selection="$("$HOME/.local/bin/git-switch-branch")" || return $?
  [ -n "$selection" ] || return 0
  local IFS=$'\t'
  read -r action value <<EOF
$selection
EOF
  case "$action" in
    checkout)
      git checkout "$value"
      ;;
    cd)
      cd "$value" && _worktree_sync_tmux_state
      ;;
    *)
      echo "Error: unknown git-switch-branch action: $action" >&2
      return 1
      ;;
  esac
}

alias db > /dev/null && unalias db
function db() {
  "$HOME/.local/bin/git-delete-branch"
}
```

Replace the bash `b` function in `roles/macos/templates/dotfiles/bash_profile` with:

```bash
b() {
  local selection action value
  selection="$("$HOME/.local/bin/git-switch-branch")" || return $?
  [ -n "$selection" ] || return 0
  local IFS=$'\t'
  read -r action value <<EOF
$selection
EOF
  case "$action" in
    checkout)
      git checkout "$value"
      ;;
    cd)
      cd "$value" && _worktree_sync_tmux_state
      ;;
    *)
      echo "Error: unknown git-switch-branch action: $action" >&2
      return 1
      ;;
  esac
}
```

- [ ] **Step 4: Run syntax checks and the temporary shell smoke script**

Run:

```bash
zsh -n roles/common/templates/dotfiles/zshrc
bash -n roles/macos/templates/dotfiles/bash_profile
bash /tmp/branch-helper-shell-smoke.sh
```

Expected:
- `zsh -n` exits 0
- `bash -n` exits 0
- the zsh smoke path prints the linked worktree path for `b`
- the zsh smoke path deletes `feature/free`
- the zsh smoke path exits non-zero on the dirty linked worktree and prints its path
- the bash smoke path prints the linked worktree path for `b`

- [ ] **Step 5: Commit the shell wrapper changes**

Run:

```bash
~/.codex/skills/committing-changes/commit.sh -m "Wire b and db through worktree-aware branch helpers" \
  roles/common/templates/dotfiles/zshrc \
  roles/macos/templates/dotfiles/bash_profile
```

Expected: one commit containing only the wrapper changes.

### Task 4: Run repository-level verification and final manual checks

**Files:**
- Verify only: `roles/common/files/bin/git-switch-branch`
- Verify only: `roles/common/files/bin/git-delete-branch`
- Verify only: `roles/common/templates/dotfiles/zshrc`
- Verify only: `roles/macos/templates/dotfiles/bash_profile`
- Verify only: `roles/common/tasks/main.yml`

- [ ] **Step 1: Run the helper tests and Ansible syntax check**

Run:

```bash
bash roles/common/files/bin/git-switch-branch.test
bash roles/common/files/bin/git-delete-branch.test
ansible-playbook playbook.yml --syntax-check
```

Expected:
- both helper tests pass
- `ansible-playbook` exits 0 with only the implicit-localhost warnings already seen in this repo

- [ ] **Step 2: Provision from the worktree so the installed helpers and dotfiles match the repo**

Run: `bin/provision`
Expected: PASS with the new `git-delete-branch` install task, the updated `~/.zshrc`, and the updated `~/.bash_profile` applied successfully.

- [ ] **Step 3: Run installed-shell manual verification for `b` and `db`**

Run:

```bash
tmpdir="$(mktemp -d)"
repo="$tmpdir/repo"
linked="$tmpdir/linked"
dirty="$tmpdir/dirty"
bindir="$tmpdir/bin"
mkdir -p "$bindir"

cat > "$bindir/fzf" <<'EOF'
#!/usr/bin/env bash
set -eu
input="$(cat)"
selected="$(printf '%s\n' "$input" | grep -F -m 1 -- "${FAKE_FZF_MATCH:?}" || true)"
[ -n "$selected" ] || exit 1
printf '%s\n' "$selected"
EOF
chmod +x "$bindir/fzf"

GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
git init -qb main "$repo"
GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
git -C "$repo" commit -q --allow-empty -m init
git -C "$repo" branch feature/free
git -C "$repo" worktree add -q -b feature/linked "$linked"
git -C "$repo" worktree add -q -b feature/dirty "$dirty"
echo dirty > "$dirty/file.txt"

PATH="$bindir:$PATH" FAKE_FZF_MATCH="+ feature/linked" zsh -ic "cd '$repo' && b >/dev/null && pwd"
PATH="$bindir:$PATH" FAKE_FZF_MATCH="  feature/free" zsh -ic "cd '$repo' && db >/dev/null && git branch --list feature/free"
PATH="$bindir:$PATH" FAKE_FZF_MATCH="+ feature/dirty" zsh -ic "cd '$repo' && db" || true
```

Expected:
- first command prints the absolute path of `$linked`
- second command prints nothing because `feature/free` was deleted
- third command exits non-zero and prints a message containing the `$dirty` path

- [ ] **Step 4: Confirm final repository state**

Run:

```bash
git status --short
git log --oneline --decorate -n 5
```

Expected:
- only the intended tracked files are modified
- the last three commits correspond to Task 1, Task 2, and Task 3
