# Codex Worktree Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor machine-managed worktree helpers into installed scripts and add a global Codex `PreToolUse` guardrail that blocks raw `git worktree add/remove` in favor of `worktree-start` and `worktree-delete`.

**Architecture:** Extract the duplicated worktree logic from the zsh and bash templates into shared helper executables under `roles/common/files/bin/`, then leave only thin shell wrappers for parent-shell `cd` behavior. Add a separate installed hook helper plus Codex config/hook provisioning in `roles/common/tasks/main.yml` so the policy is enforced at the user-level Codex layer without touching global instruction text.

**Tech Stack:** Ansible, zsh, bash, POSIX shell helper scripts, Python 3 for idempotent config file mutation, jq for JSON assertions in tests, Codex CLI hooks.

---

## File Structure

### New files

- `roles/common/files/bin/worktree-lib.sh`
  Shared shell library for worktree helper implementations and path/tool lookup.
- `roles/common/files/bin/worktree-start`
  Executable source of truth for creating a linked worktree.
- `roles/common/files/bin/worktree-delete`
  Executable source of truth for deleting the current linked worktree.
- `roles/common/files/bin/worktree-done`
  Executable source of truth for merge/push/remove completion flow.
- `roles/common/files/bin/worktree-merge`
  Executable source of truth for local merge-back flow without removal.
- `roles/common/files/bin/worktree-start.test`
  Regression harness for the extracted `worktree-start` executable.
- `roles/common/files/bin/worktree-lifecycle.test`
  Regression harness for `worktree-delete`, `worktree-done`, and `worktree-merge`.
- `roles/common/files/bin/worktree-wrapper.test`
  Regression harness proving the zsh/bash wrappers delegate to installed helpers and `cd` in the parent shell.
- `roles/common/files/bin/codex-block-worktree-commands`
  Codex hook helper that denies raw `git worktree add/remove`.
- `roles/common/files/bin/codex-block-worktree-commands.test`
  Regression harness for the hook helper’s JSON input/output behavior.
- `tests/codex-worktree-hook-provisioning.sh`
  Repo-level regression check for install tasks, feature flag management, and hook provisioning.

### Modified files

- `roles/common/templates/dotfiles/zshrc`
  Replace embedded worktree implementations with thin wrappers around installed helpers.
- `roles/macos/templates/dotfiles/bash_profile`
  Replace embedded worktree implementations with thin wrappers around installed helpers.
- `roles/common/tasks/main.yml`
  Install the new helper scripts, ensure `codex_hooks` is enabled, and merge the managed `~/.codex/hooks.json` entry.

## Task 1: Extract `worktree-start` Into An Installed Helper

**Files:**
- Create: `roles/common/files/bin/worktree-lib.sh`
- Create: `roles/common/files/bin/worktree-start`
- Create: `roles/common/files/bin/worktree-start.test`
- Create: `roles/common/files/bin/worktree-wrapper.test`
- Modify: `roles/common/templates/dotfiles/zshrc`
- Modify: `roles/macos/templates/dotfiles/bash_profile`
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Write the failing executable and wrapper tests**

Create `roles/common/files/bin/worktree-start.test` with this content:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/worktree-start"

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

repo="$TMPROOT/repo"
git init -qb main "$repo"
git -C "$repo" commit -q --allow-empty -m init

mkdir -p "$repo/.coding-agent"
printf '%s\n' 'note' >"$repo/.coding-agent/example.md"
mkdir -p "$repo/.claude"
printf '%s\n' '{"permissions":{"allow":[]}}' >"$repo/.claude/settings.local.json"

path="$("$SCRIPT" --branch feature/test --print-path 2>"$TMPROOT/stderr")"

[ "$path" = "$TMPROOT/repo-feature-test" ] || {
  printf 'expected printed path, got %q\n' "$path" >&2
  exit 1
}

[ -d "$path/.git" ] || [ -f "$path/.git" ] || {
  printf 'expected worktree metadata at %s\n' "$path" >&2
  exit 1
}

[ -f "$path/.coding-agent/example.md" ] || {
  printf 'expected .coding-agent copy in %s\n' "$path" >&2
  exit 1
}

[ -f "$path/.claude/settings.local.json" ] || {
  printf 'expected settings.local.json copy in %s\n' "$path" >&2
  exit 1
}

printf 'PASS  worktree-start --print-path creates worktree and copies bootstrap files\n'
```

Create `roles/common/files/bin/worktree-wrapper.test` with this content:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$(cd "$SCRIPT_DIR/../../../.." && pwd)")"
ZSHRC="$ROOT/roles/common/templates/dotfiles/zshrc"
BASH_PROFILE="$ROOT/roles/macos/templates/dotfiles/bash_profile"
ZSH_BIN="$(command -v zsh)"
BASH_BIN="$(command -v bash)"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
mkdir -p "$TMPROOT/home/.local/bin"

cat >"$TMPROOT/home/.local/bin/worktree-start" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$HOME/target-worktree"
EOF
chmod +x "$TMPROOT/home/.local/bin/worktree-start"

extract_function() {
  local source_file="$1"
  local output_file="$2"
  awk '
    /^worktree-start\(\) \{$/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
  ' "$source_file" >"$output_file"
}

extract_function "$ZSHRC" "$TMPROOT/worktree-start.zsh"
extract_function "$BASH_PROFILE" "$TMPROOT/worktree-start.bash"

cat >"$TMPROOT/run.zsh" <<EOF
set -eu
HOME="$TMPROOT/home"
source "$TMPROOT/worktree-start.zsh"
mkdir -p "\$HOME/target-worktree"
worktree-start --branch feature/test >/dev/null
print -r -- "\$PWD"
EOF

output="$(HOME="$TMPROOT/home" "$ZSH_BIN" -f "$TMPROOT/run.zsh")"
[ "$output" = "$TMPROOT/home/target-worktree" ] || {
  printf 'expected zsh wrapper to cd into stub path, got %q\n' "$output" >&2
  exit 1
}

printf 'PASS  zsh wrapper cds into executable output\n'

cat >"$TMPROOT/run.bash" <<EOF
set -eu
HOME="$TMPROOT/home"
source "$TMPROOT/worktree-start.bash"
mkdir -p "\$HOME/target-worktree"
worktree-start --branch feature/test >/dev/null
printf '%s\n' "\$PWD"
EOF

output="$(HOME="$TMPROOT/home" "$BASH_BIN" --noprofile --norc "$TMPROOT/run.bash")"
[ "$output" = "$TMPROOT/home/target-worktree" ] || {
  printf 'expected bash wrapper to cd into stub path, got %q\n' "$output" >&2
  exit 1
}

printf 'PASS  bash wrapper cds into executable output\n'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
bash roles/common/files/bin/worktree-start.test
bash roles/common/files/bin/worktree-wrapper.test
```

Expected:

- `worktree-start.test` fails with `ERROR: .../worktree-start is not executable`
- `worktree-wrapper.test` fails because the current shell function body is still the inline implementation, not a wrapper around `~/.local/bin/worktree-start`

- [ ] **Step 3: Write the minimal helper, install task, and wrapper implementation**

Create `roles/common/files/bin/worktree-lib.sh`:

```bash
#!/usr/bin/env bash
set -u

worktree_cmd() {
  local cmd="$1"
  local candidates=()
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    candidates+=("/opt/homebrew/bin/$cmd")
  fi
  candidates+=("/usr/local/bin/$cmd" "/usr/bin/$cmd" "/bin/$cmd")
  local path
  for path in "${candidates[@]}"; do
    if [[ -x "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  printf '%s\n' "$cmd"
}

worktree_repo_root() {
  local root
  root=$(GIT_DIR= GIT_WORK_TREE= "$(worktree_cmd git)" rev-parse --show-toplevel 2>/dev/null) || true
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  "$(worktree_cmd git)" rev-parse --show-toplevel 2>/dev/null
}

worktree_sync_coding_agent_new_files() {
  local src="$1"
  local dst="$2"
  if [[ ! -d "$src" ]]; then
    return 0
  fi
  "$(worktree_cmd mkdir)" -p "$dst"
  "$(worktree_cmd cp)" -R -n "${src}/." "${dst}/"
}

worktree_sync_tmux_state() {
  if command -v tmux-agent-worktree >/dev/null 2>&1; then
    tmux-agent-worktree sync-current >/dev/null 2>&1 || true
  fi
}
```

Create `roles/common/files/bin/worktree-start`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./worktree-lib.sh
source "$SCRIPT_DIR/worktree-lib.sh"

branch=""
path=""
start_point="HEAD"
print_path="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--branch) branch="${2:-}"; shift 2 ;;
    -p|--path) path="${2:-}"; shift 2 ;;
    -f|--from) start_point="${2:-}"; shift 2 ;;
    --print-path) print_path="true"; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: worktree-start <branch> [path]
       worktree-start --branch <branch> [--path <path>] [--from <start-point>] [--print-path]
EOF
      exit 0
      ;;
    -*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$branch" ]]; then
        branch="$1"
      elif [[ -z "$path" ]]; then
        path="$1"
      else
        printf 'Error: unexpected argument: %s\n' "$1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

[[ -n "$branch" ]] || { printf 'Error: branch name is required\n' >&2; exit 1; }

repo_root="$(worktree_repo_root)" || { printf 'Error: not inside a git repository\n' >&2; exit 1; }
if [[ -z "$path" ]]; then
  repo_name="$("$(worktree_cmd basename)" "$repo_root")"
  parent_dir="$("$(worktree_cmd dirname)" "$repo_root")"
  safe_branch="${branch//\//-}"
  path="${parent_dir}/${repo_name}-${safe_branch}"
fi

"$(worktree_cmd git)" -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" && {
  printf 'Error: branch already exists: %s\n' "$branch" >&2
  exit 1
}

[[ ! -e "$path" ]] || { printf 'Error: path already exists: %s\n' "$path" >&2; exit 1; }
"$(worktree_cmd git)" -C "$repo_root" rev-parse --verify "$start_point" >/dev/null 2>&1 || {
  printf 'Error: invalid start point: %s\n' "$start_point" >&2
  exit 1
}

"$(worktree_cmd git)" -C "$repo_root" worktree add -b "$branch" "$path" "$start_point"
worktree_sync_coding_agent_new_files "$repo_root/.coding-agent" "$path/.coding-agent"

if [[ ! -e "$path/.claude/settings.local.json" ]]; then
  settings_source="$repo_root/.claude/settings.local.json"
  [[ -f "$settings_source" ]] || settings_source="$HOME/.claude/settings.local.json"
  if [[ -f "$settings_source" ]]; then
    "$(worktree_cmd mkdir)" -p "$path/.claude"
    "$(worktree_cmd cp)" -p "$settings_source" "$path/.claude/settings.local.json"
  fi
fi

if command -v claude-trust-directory >/dev/null 2>&1; then
  claude-trust-directory "$path" 2>/dev/null || true
fi

if command -v mise >/dev/null 2>&1; then
  mise trust "$path" >/dev/null 2>&1 || true
fi

if [[ "$print_path" == "true" ]]; then
  printf '%s\n' "$path"
else
  printf '==> Worktree created:\n'
  printf '    Branch: %s\n' "$branch"
fi
```

Add this install task block near the other `~/.local/bin` helper installs in `roles/common/tasks/main.yml`:

```yaml
- name: Install worktree helper scripts
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/{{ item }}'
    src: '{{ playbook_dir }}/roles/common/files/bin/{{ item }}'
    mode: '0755'
  loop:
    - worktree-lib.sh
    - worktree-start
```

Replace the zsh `worktree-start()` body in `roles/common/templates/dotfiles/zshrc` with:

```bash
worktree-start() {
  local path
  path="$("$HOME/.local/bin/worktree-start" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
  echo "==> Worktree created:"
  echo "    Path: $path"
}
```

Replace the bash `worktree-start()` body in `roles/macos/templates/dotfiles/bash_profile` with:

```bash
worktree-start() {
  local path
  path="$("$HOME/.local/bin/worktree-start" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
  echo "==> Worktree created:"
  echo "    Path: $path"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
bash roles/common/files/bin/worktree-start.test
bash roles/common/files/bin/worktree-wrapper.test
```

Expected:

- `PASS  worktree-start --print-path creates worktree and copies bootstrap files`
- `PASS  zsh wrapper cds into executable output`
- `PASS  bash wrapper cds into executable output`

- [ ] **Step 5: Commit**

Run:

```bash
git add \
  roles/common/files/bin/worktree-lib.sh \
  roles/common/files/bin/worktree-start \
  roles/common/files/bin/worktree-start.test \
  roles/common/files/bin/worktree-wrapper.test \
  roles/common/templates/dotfiles/zshrc \
  roles/macos/templates/dotfiles/bash_profile \
  roles/common/tasks/main.yml
git commit -m "Extract worktree-start into helper script"
```

## Task 2: Extract `worktree-delete`, `worktree-done`, and `worktree-merge`

**Files:**
- Create: `roles/common/files/bin/worktree-delete`
- Create: `roles/common/files/bin/worktree-done`
- Create: `roles/common/files/bin/worktree-merge`
- Create: `roles/common/files/bin/worktree-lifecycle.test`
- Modify: `roles/common/templates/dotfiles/zshrc`
- Modify: `roles/macos/templates/dotfiles/bash_profile`
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Write the failing lifecycle test**

Create `roles/common/files/bin/worktree-lifecycle.test`:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DELETE_SCRIPT="$SCRIPT_DIR/worktree-delete"
MERGE_SCRIPT="$SCRIPT_DIR/worktree-merge"
DONE_SCRIPT="$SCRIPT_DIR/worktree-done"

if [ ! -x "$DELETE_SCRIPT" ] || [ ! -x "$MERGE_SCRIPT" ] || [ ! -x "$DONE_SCRIPT" ]; then
  printf 'ERROR: lifecycle scripts are not executable yet\n' >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

GIT_AUTHOR_NAME=test
GIT_AUTHOR_EMAIL=test@example.com
GIT_COMMITTER_NAME=test
GIT_COMMITTER_EMAIL=test@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

create_repo() {
  local name="$1"
  local origin="$TMPROOT/${name}-origin.git"
  local repo="$TMPROOT/${name}-repo"
  git init -q --bare "$origin"
  git init -qb main "$repo"
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" push -q -u origin main
  printf '%s\n' "$repo"
}

delete_repo="$(create_repo delete)"
delete_wt="$TMPROOT/delete-wt"
git -C "$delete_repo" worktree add -q -b feature/delete "$delete_wt"

( cd "$delete_wt" && "$DELETE_SCRIPT" ) >"$TMPROOT/worktree-delete.out" 2>"$TMPROOT/worktree-delete.err"

git -C "$delete_repo" show-ref --verify --quiet refs/heads/feature/delete && {
  printf 'expected feature/delete branch to be removed\n' >&2
  exit 1
}

git -C "$delete_repo" worktree list --porcelain | grep -Fq "worktree $delete_wt" && {
  printf 'expected linked worktree metadata to be removed\n' >&2
  exit 1
}

printf 'PASS  lifecycle helper removes clean linked worktree and branch\n'

merge_repo="$(create_repo merge)"
merge_wt="$TMPROOT/merge-wt"
git -C "$merge_repo" worktree add -q -b feature/merge "$merge_wt"
printf '%s\n' 'merge change' >"$merge_wt/merge.txt"
git -C "$merge_wt" add merge.txt
git -C "$merge_wt" commit -q -m 'merge change'

merge_path="$( cd "$merge_wt" && "$MERGE_SCRIPT" --print-path )"
[ "$merge_path" = "$merge_repo" ] || {
  printf 'expected merge helper to return main path, got %q\n' "$merge_path" >&2
  exit 1
}

[ -f "$merge_repo/merge.txt" ] || {
  printf 'expected merge helper to update main worktree\n' >&2
  exit 1
}

printf 'PASS  lifecycle helper merges branch into main worktree\n'

done_repo="$(create_repo done)"
done_wt="$TMPROOT/done-wt"
git -C "$done_repo" worktree add -q -b feature/done "$done_wt"
printf '%s\n' 'done change' >"$done_wt/done.txt"
git -C "$done_wt" add done.txt
git -C "$done_wt" commit -q -m 'done change'

done_path="$( cd "$done_wt" && "$DONE_SCRIPT" --print-path )"
[ "$done_path" = "$done_repo" ] || {
  printf 'expected done helper to return main path, got %q\n' "$done_path" >&2
  exit 1
}

[ -f "$done_repo/done.txt" ] || {
  printf 'expected done helper to update main worktree\n' >&2
  exit 1
}

git -C "$done_repo" show-ref --verify --quiet refs/heads/feature/done && {
  printf 'expected feature/done branch to be removed\n' >&2
  exit 1
}

git -C "$done_repo" worktree list --porcelain | grep -Fq "worktree $done_wt" && {
  printf 'expected done worktree metadata to be removed\n' >&2
  exit 1
}

printf 'PASS  lifecycle helper finishes branch and removes worktree\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash roles/common/files/bin/worktree-lifecycle.test
```

Expected:

- `ERROR: lifecycle scripts are not executable yet`

- [ ] **Step 3: Write the lifecycle executables and wrapper updates**

Create `roles/common/files/bin/worktree-delete`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./worktree-lib.sh
source "$SCRIPT_DIR/worktree-lib.sh"

print_path="false"
if [[ "${1:-}" == "--print-path" ]]; then
  print_path="true"
  shift
fi

worktree_main_branch() {
  local origin_head
  origin_head="$("$(worktree_cmd git)" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$origin_head" ]]; then
    printf '%s\n' "${origin_head#origin/}"
  elif "$(worktree_cmd git)" show-ref --verify --quiet refs/heads/main; then
    printf '%s\n' main
  else
    printf '%s\n' master
  fi
}

worktree_main_path() {
  local main_branch="$1" line main_path branch_name
  main_path=""
  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      main_path="${line#worktree }"
    elif [[ "$line" == branch\ refs/heads/* ]]; then
      branch_name="${line#branch refs/heads/}"
      if [[ "$branch_name" == "$main_branch" ]]; then
        printf '%s\n' "$main_path"
        return 0
      fi
      main_path=""
    fi
  done < <("$(worktree_cmd git)" worktree list --porcelain)
  return 1
}

repo_root="$(worktree_repo_root)" || { printf 'Error: not inside a git repository\n' >&2; exit 1; }
current_branch="$("$(worktree_cmd git)" -C "$repo_root" branch --show-current)"
[[ -n "$current_branch" ]] || { printf 'Error: detached HEAD; checkout a branch first\n' >&2; exit 1; }

main_branch="$(worktree_main_branch)"
[[ "$current_branch" != "$main_branch" ]] || {
  printf 'Error: already on %s; this command is for non-main worktrees\n' "$main_branch" >&2
  exit 1
}

[[ -z "$("$(worktree_cmd git)" -C "$repo_root" status --porcelain)" ]] || {
  printf 'Error: worktree has uncommitted changes; commit or stash first\n' >&2
  exit 1
}

main_path="$(worktree_main_path "$main_branch")" || {
  printf 'Error: could not find main worktree for branch %s\n' "$main_branch" >&2
  exit 1
}

"$(worktree_cmd git)" -C "$main_path" worktree remove "$repo_root"
"$(worktree_cmd git)" -C "$main_path" branch -D "$current_branch"
if [[ "$print_path" == "true" ]]; then
  printf '%s\n' "$main_path"
else
  printf '==> Removed worktree and deleted branch:\n'
  printf '    Branch: %s\n' "$current_branch"
  printf '    Path: %s\n' "$repo_root"
fi
```

Create `roles/common/files/bin/worktree-merge`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./worktree-lib.sh
source "$SCRIPT_DIR/worktree-lib.sh"

worktree_main_branch() {
  local origin_head
  origin_head="$("$(worktree_cmd git)" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$origin_head" ]]; then
    printf '%s\n' "${origin_head#origin/}"
  elif "$(worktree_cmd git)" show-ref --verify --quiet refs/heads/main; then
    printf '%s\n' main
  else
    printf '%s\n' master
  fi
}

worktree_main_path() {
  local main_branch="$1" line main_path branch_name
  main_path=""
  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      main_path="${line#worktree }"
    elif [[ "$line" == branch\ refs/heads/* ]]; then
      branch_name="${line#branch refs/heads/}"
      if [[ "$branch_name" == "$main_branch" ]]; then
        printf '%s\n' "$main_path"
        return 0
      fi
      main_path=""
    fi
  done < <("$(worktree_cmd git)" worktree list --porcelain)
  return 1
}

repo_root="$(worktree_repo_root)" || { printf 'Error: not inside a git repository\n' >&2; exit 1; }
current_branch="$("$(worktree_cmd git)" -C "$repo_root" branch --show-current)"
[[ -n "$current_branch" ]] || { printf 'Error: detached HEAD; checkout a branch first\n' >&2; exit 1; }

main_branch="$(worktree_main_branch)"
[[ "$current_branch" != "$main_branch" ]] || {
  printf 'Error: already on %s; this command is for non-main worktrees\n' "$main_branch" >&2
  exit 1
}

[[ -z "$("$(worktree_cmd git)" -C "$repo_root" status --porcelain)" ]] || {
  printf 'Error: worktree has uncommitted changes; commit or stash first\n' >&2
  exit 1
}

main_path="$(worktree_main_path "$main_branch")" || {
  printf 'Error: could not find main worktree for branch %s\n' "$main_branch" >&2
  exit 1
}

[[ -z "$("$(worktree_cmd git)" -C "$main_path" status --porcelain)" ]] || {
  printf 'Error: main worktree has uncommitted changes; clean it first\n' >&2
  exit 1
}

"$(worktree_cmd git)" -C "$main_path" checkout "$main_branch"
"$(worktree_cmd git)" -C "$main_path" merge "$current_branch"
if [[ "${1:-}" == "--print-path" ]]; then
  printf '%s\n' "$main_path"
else
  printf '==> Merged %s into %s:\n' "$current_branch" "$main_branch"
  printf '    Branch: %s\n' "$current_branch"
  printf '    Main: %s\n' "$main_path"
fi
```

Create `roles/common/files/bin/worktree-done`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./worktree-lib.sh
source "$SCRIPT_DIR/worktree-lib.sh"

worktree_main_branch() {
  local origin_head
  origin_head="$("$(worktree_cmd git)" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$origin_head" ]]; then
    printf '%s\n' "${origin_head#origin/}"
  elif "$(worktree_cmd git)" show-ref --verify --quiet refs/heads/main; then
    printf '%s\n' main
  else
    printf '%s\n' master
  fi
}

worktree_main_path() {
  local main_branch="$1" line main_path branch_name
  main_path=""
  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      main_path="${line#worktree }"
    elif [[ "$line" == branch\ refs/heads/* ]]; then
      branch_name="${line#branch refs/heads/}"
      if [[ "$branch_name" == "$main_branch" ]]; then
        printf '%s\n' "$main_path"
        return 0
      fi
      main_path=""
    fi
  done < <("$(worktree_cmd git)" worktree list --porcelain)
  return 1
}

repo_root="$(worktree_repo_root)" || { printf 'Error: not inside a git repository\n' >&2; exit 1; }
current_branch="$("$(worktree_cmd git)" -C "$repo_root" branch --show-current)"
[[ -n "$current_branch" ]] || { printf 'Error: detached HEAD; checkout a branch first\n' >&2; exit 1; }

main_branch="$(worktree_main_branch)"
[[ "$current_branch" != "$main_branch" ]] || {
  printf 'Error: already on %s; this command is for non-main worktrees\n' "$main_branch" >&2
  exit 1
}

[[ -z "$("$(worktree_cmd git)" -C "$repo_root" status --porcelain)" ]] || {
  printf 'Error: worktree has uncommitted changes; commit or stash first\n' >&2
  exit 1
}

main_path="$(worktree_main_path "$main_branch")" || {
  printf 'Error: could not find main worktree for branch %s\n' "$main_branch" >&2
  exit 1
}

[[ -z "$("$(worktree_cmd git)" -C "$main_path" status --porcelain)" ]] || {
  printf 'Error: main worktree has uncommitted changes; clean it first\n' >&2
  exit 1
}

"$(worktree_cmd git)" -C "$main_path" checkout "$main_branch"
"$(worktree_cmd git)" -C "$main_path" fetch || true
if "$(worktree_cmd git)" -C "$main_path" merge-base --is-ancestor "$current_branch" "origin/${main_branch}" 2>/dev/null; then
  "$(worktree_cmd git)" -C "$main_path" merge --ff-only "origin/${main_branch}"
else
  "$(worktree_cmd git)" -C "$repo_root" rebase "origin/${main_branch}"
  "$(worktree_cmd git)" -C "$main_path" merge "$current_branch"
  "$(worktree_cmd git)" -C "$main_path" push
fi

worktree_sync_coding_agent_new_files "$repo_root/.coding-agent" "$main_path/.coding-agent"
"$(worktree_cmd git)" -C "$main_path" worktree remove "$repo_root"
"$(worktree_cmd git)" -C "$main_path" branch -D "$current_branch"
if [[ "${1:-}" == "--print-path" ]]; then
  printf '%s\n' "$main_path"
else
  printf '==> Merged %s into %s and removed worktree:\n' "$current_branch" "$main_branch"
  printf '    Branch: %s\n' "$current_branch"
  printf '    Path: %s\n' "$repo_root"
fi
```

Extend the install loop in `roles/common/tasks/main.yml`:

```yaml
  loop:
    - worktree-lib.sh
    - worktree-start
    - worktree-delete
    - worktree-done
    - worktree-merge
```

Replace the zsh wrappers in `roles/common/templates/dotfiles/zshrc` with:

```bash
worktree-merge() {
  local path
  path="$("$HOME/.local/bin/worktree-merge" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
}

worktree-delete() {
  local path
  path="$("$HOME/.local/bin/worktree-delete" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
}

worktree-done() {
  local path
  path="$("$HOME/.local/bin/worktree-done" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
}
```

Apply the same wrapper pattern in `roles/macos/templates/dotfiles/bash_profile`.

- [ ] **Step 4: Run the lifecycle test and wrapper smoke checks**

Run:

```bash
bash roles/common/files/bin/worktree-lifecycle.test
bash roles/common/files/bin/worktree-wrapper.test
```

Expected:

- `PASS  lifecycle helper removes clean linked worktree and branch`
- `PASS  lifecycle helper merges branch into main worktree`
- `PASS  lifecycle helper finishes branch and removes worktree`
- wrapper test still passes after the lifecycle wrapper changes

- [ ] **Step 5: Commit**

Run:

```bash
git add \
  roles/common/files/bin/worktree-delete \
  roles/common/files/bin/worktree-done \
  roles/common/files/bin/worktree-merge \
  roles/common/files/bin/worktree-lifecycle.test \
  roles/common/templates/dotfiles/zshrc \
  roles/macos/templates/dotfiles/bash_profile \
  roles/common/tasks/main.yml
git commit -m "Extract worktree lifecycle helpers"
```

## Task 3: Add The Codex Worktree Blocking Hook Helper

**Files:**
- Create: `roles/common/files/bin/codex-block-worktree-commands`
- Create: `roles/common/files/bin/codex-block-worktree-commands.test`
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Write the failing hook-helper test**

Create `roles/common/files/bin/codex-block-worktree-commands.test`:

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/codex-block-worktree-commands"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

run_case() {
  local name="$1"
  local command="$2"
  local expected="$3"
  local output

  output="$(jq -n --arg command "$command" '{tool_input:{command:$command}}' | "$SCRIPT")"
  if [[ "$output" == *"$expected"* ]]; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    printf '      output: %s\n' "$output" >&2
    exit 1
  fi
}

run_case "blocks raw worktree add" 'git worktree add -b foo ../foo' 'use worktree-start'
run_case "blocks raw worktree remove" 'git worktree remove ../foo' 'use worktree-delete'

allow_output="$(jq -n --arg command 'worktree-start foo' '{tool_input:{command:$command}}' | "$SCRIPT")"
[ -z "$allow_output" ] || {
  printf 'expected helper invocation to pass through, got %q\n' "$allow_output" >&2
  exit 1
}

printf 'PASS  helper invocation passes through\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash roles/common/files/bin/codex-block-worktree-commands.test
```

Expected:

- `ERROR: .../codex-block-worktree-commands is not executable`

- [ ] **Step 3: Write the hook helper and install it**

Create `roles/common/files/bin/codex-block-worktree-commands`:

```bash
#!/usr/bin/env bash
set -euo pipefail

command="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"

if [[ -z "$command" ]]; then
  exit 0
fi

if printf '%s\n' "$command" | grep -Eq '(^|[[:space:];(])git[[:space:]]+worktree[[:space:]]+add([[:space:]]|$)'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Do not run git worktree add directly. Use worktree-start instead."
    }
  }'
  exit 0
fi

if printf '%s\n' "$command" | grep -Eq '(^|[[:space:];(])git[[:space:]]+worktree[[:space:]]+remove([[:space:]]|$)'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Do not run git worktree remove directly. Use worktree-delete instead."
    }
  }'
  exit 0
fi
```

Extend the install loop in `roles/common/tasks/main.yml`:

```yaml
  loop:
    - worktree-lib.sh
    - worktree-start
    - worktree-delete
    - worktree-done
    - worktree-merge
    - codex-block-worktree-commands
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
bash roles/common/files/bin/codex-block-worktree-commands.test
```

Expected:

- `PASS  blocks raw worktree add`
- `PASS  blocks raw worktree remove`
- `PASS  helper invocation passes through`

- [ ] **Step 5: Commit**

Run:

```bash
git add \
  roles/common/files/bin/codex-block-worktree-commands \
  roles/common/files/bin/codex-block-worktree-commands.test \
  roles/common/tasks/main.yml
git commit -m "Add Codex worktree blocking hook helper"
```

## Task 4: Provision `codex_hooks` And Merge `~/.codex/hooks.json`

**Files:**
- Create: `tests/codex-worktree-hook-provisioning.sh`
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Write the failing provisioning regression test**

Create `tests/codex-worktree-hook-provisioning.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
TASKS="$ROOT/roles/common/tasks/main.yml"

require_literal() {
  local needle="$1"
  if ! grep -Fq "$needle" "$TASKS"; then
    printf 'missing %s in %s\n' "$needle" "$TASKS" >&2
    exit 1
  fi
}

require_literal "codex-block-worktree-commands"
require_literal "codex_hooks = true"
require_literal "~/.codex/hooks.json"
require_literal "\"permissionDecision\": \"deny\""

printf 'PASS  codex hook provisioning literals present\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/codex-worktree-hook-provisioning.sh
```

Expected:

- failure reporting at least one missing literal because `roles/common/tasks/main.yml` does not yet manage the feature flag or `hooks.json`

- [ ] **Step 3: Implement the Ansible config and hook merge tasks**

Add this task after the existing `~/.codex/config.toml` trust-management tasks in `roles/common/tasks/main.yml`:

```yaml
- name: Enable Codex hooks in ~/.codex/config.toml
  shell: |
    python3 - <<'PY'
    import os
    from pathlib import Path

    config_path = Path(os.environ["CONFIG_FILE"])
    text = config_path.read_text() if config_path.exists() else ""

    if "[features]" not in text:
      text = text.rstrip() + "\n\n[features]\ncodex_hooks = true\n"
      changed = True
    elif "codex_hooks = true" not in text:
      text = text.replace("[features]\n", "[features]\ncodex_hooks = true\n", 1)
      changed = True
    else:
      changed = False

    if changed:
      config_path.write_text(text)
      os.chmod(config_path, 0o600)
      print("changed")
    else:
      print("unchanged")
    PY
  environment:
    CONFIG_FILE: '{{ ansible_facts["user_dir"] }}/.codex/config.toml'
  register: codex_hooks_feature_result
  changed_when: codex_hooks_feature_result.stdout.strip() == 'changed'
```

Add this task immediately after it:

```yaml
- name: Merge managed Codex worktree hook into ~/.codex/hooks.json
  shell: |
    python3 - <<'PY'
    import json
    import os
    from pathlib import Path

    hooks_path = Path(os.environ["HOOKS_FILE"])
    if hooks_path.exists():
      data = json.loads(hooks_path.read_text() or "{}")
    else:
      data = {}

    managed = {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "~/.local/bin/codex-block-worktree-commands",
          "statusMessage": "Checking worktree command policy",
        }
      ],
    }

    hooks = data.setdefault("hooks", {})
    groups = hooks.setdefault("PreToolUse", [])

    if managed not in groups:
      groups.append(managed)
      hooks_path.parent.mkdir(parents=True, exist_ok=True)
      hooks_path.write_text(json.dumps(data, indent=2) + "\n")
      os.chmod(hooks_path, 0o600)
      print("changed")
    else:
      print("unchanged")
    PY
  environment:
    HOOKS_FILE: '{{ ansible_facts["user_dir"] }}/.codex/hooks.json'
  register: codex_worktree_hook_result
  changed_when: codex_worktree_hook_result.stdout.strip() == 'changed'
```

- [ ] **Step 4: Run the provisioning regression tests**

Run:

```bash
bash tests/codex-worktree-hook-provisioning.sh
bash roles/common/files/bin/codex-block-worktree-commands.test
bash roles/common/files/bin/worktree-start.test
bash roles/common/files/bin/worktree-lifecycle.test
bash roles/common/files/bin/worktree-wrapper.test
```

Expected:

- provisioning test prints `PASS  codex hook provisioning literals present`
- all helper tests print `PASS` lines and exit `0`

- [ ] **Step 5: Commit**

Run:

```bash
git add \
  tests/codex-worktree-hook-provisioning.sh \
  roles/common/tasks/main.yml
git commit -m "Provision Codex worktree hook"
```

## Task 5: Apply And Verify On A Real Managed Environment

**Files:**
- Modify: none

- [ ] **Step 1: Run the full targeted regression set**

Run:

```bash
bash roles/common/files/bin/worktree-start.test
bash roles/common/files/bin/worktree-lifecycle.test
bash roles/common/files/bin/worktree-wrapper.test
bash roles/common/files/bin/codex-block-worktree-commands.test
bash tests/codex-worktree-hook-provisioning.sh
```

Expected:

- every command exits `0`
- every script prints only `PASS` lines

- [ ] **Step 2: Apply the bootstrap changes**

Run:

```bash
bin/provision
```

Expected:

- Ansible reports changes only in the new helper install tasks, the wrapper-managed dotfiles, and the Codex config/hook tasks

- [ ] **Step 3: Verify the deployed Codex config and hook files**

Run:

```bash
rg -n '^codex_hooks = true$' ~/.codex/config.toml
jq '.hooks.PreToolUse' ~/.codex/hooks.json
```

Expected:

- `rg` prints one matching `codex_hooks = true` line
- `jq` output includes a `Bash` matcher with `~/.local/bin/codex-block-worktree-commands`

- [ ] **Step 4: Run one empirical Codex guardrail check**

Run:

```bash
codex exec --json "Run this exact command and nothing else: git worktree add -b codex-hook-smoke ../new-machine-bootstrap-codex-hook-smoke" | tee /tmp/codex-worktree-hook-smoke.jsonl
rg -n 'use worktree-start|permissionDecisionReason|blocked|deny' /tmp/codex-worktree-hook-smoke.jsonl
```

Expected:

- Codex does not create the worktree
- the JSONL transcript contains the denial reason telling it to use `worktree-start`

- [ ] **Step 5: Verify clean git status after verification**

Run:

```bash
git status --short
```

Expected:

- no output
