# Repo Lifecycle Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the existing worktree lifecycle helpers to generic `repo-start` / `repo-end` commands with `.repo.yml`-controlled worktree-or-branch behavior.

**Architecture:** Reuse the current worktree helper behavior by moving it into `repo-start` and shared `repo-lib.sh`, then add branch mode and config resolution around it. `repo-end` owns rebase/merge/push and delegates cleanup to the existing Ruby `cleanup-branches` script after moving that script into common provisioning.

**Tech Stack:** Bash helper scripts, Ruby `cleanup-branches`, Ansible provisioning, `jq`/`yq`, shell regression tests, git worktrees, temporary bare git remotes.

---

## File Structure

- Create: `roles/common/files/bin/repo-lib.sh`
  Shared command lookup, git path helpers, `.repo.yml` mode resolution, copied worktree helpers from `worktree-lib.sh`, and tmux state publication.
- Create: `roles/common/files/bin/repo-start`
  Public start command. Parses the old `worktree-start` CLI plus `--use-worktrees` and `--no-worktrees`, resolves mode, then dispatches to worktree or branch mode.
- Create: `roles/common/files/bin/repo-end`
  Public finish command. Rebases current branch, merges into main, pushes, then calls `cleanup-branches --branch`.
- Move: `roles/macos/files/bin/cleanup-branches` to `roles/common/files/bin/cleanup-branches`
  Same Ruby implementation, common install location.
- Move: `roles/macos/files/bin/cleanup-branches.test` to `roles/common/files/bin/cleanup-branches.test`
  Same test harness, updated to run beside the common helper.
- Create: `roles/common/files/bin/repo-start.test`
  Regression tests for config resolution, worktree mode, branch mode, and JSON output.
- Create: `roles/common/files/bin/repo-end.test`
  Regression tests for merge/push/cleanup delegation and rejection paths.
- Modify: `roles/common/files/bin/codex-block-main-branch-edits`
  Denial reason uses `repo-start`.
- Modify: `roles/common/files/bin/codex-block-main-branch-edits.test`
  Expected reason uses `repo-start`.
- Modify: `roles/common/files/bin/codex-block-worktree-commands`
  Denial reasons no longer recommend removed `worktree-*` commands.
- Modify: `roles/common/files/bin/codex-block-worktree-commands.test`
  Expected reasons use `repo-start`, `repo-end`, and `cleanup-branches --branch` wording.
- Modify: `roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh`
  Replace public `worktree-*` wrappers with `repo-start`, `repo-end`, `rs`, and `re` wrappers.
- Modify: `roles/macos/templates/dotfiles/bash_profile`
  Same wrapper migration for macOS bash login shells.
- Modify: `roles/common/templates/dotfiles/gitignore`
  Add `.repo.yml`.
- Modify: `roles/common/tasks/main.yml`
  Install `repo-*`, `repo-lib.sh`, common `cleanup-branches`; remove public worktree helper install entries.
- Modify/Create tests under `tests/`
  Provisioning assertions for helper installation, wrapper migration, hook wording, and global gitignore.

## Task 1: Approve Spec And Add `repo-start` Red Tests

**Files:**
- Modify: `docs/superpowers/specs/2026-05-02-repo-lifecycle-config-design.md`
- Create: `roles/common/files/bin/repo-start.test`

- [ ] **Step 1: Confirm spec status is approved**

Verify the spec contains:

```markdown
**Status:** Approved
```

Run:

```bash
rg -n '^\*\*Status:\*\* Approved$' docs/superpowers/specs/2026-05-02-repo-lifecycle-config-design.md
```

Expected: one matching line.

- [ ] **Step 2: Write failing `repo-start` test skeleton**

Create `roles/common/files/bin/repo-start.test` with these test sections:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/repo-start"

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

create_repo() {
  local name="$1"
  local repo="$TMPROOT/$name"
  git init -qb main "$repo"
  git -C "$repo" commit -q --allow-empty -m init
  printf '%s\n' "$repo"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  grep -Fq -- "$needle" "$path" || {
    printf 'FAIL  %s\nmissing %s in %s\n' "$name" "$needle" "$path" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

assert_no_file() {
  local path="$1" name="$2"
  [ ! -e "$path" ] || {
    printf 'FAIL  %s\nexpected absent: %s\n' "$name" "$path" >&2
    exit 1
  }
  printf 'PASS  %s\n' "$name"
}

worktree_repo="$(create_repo worktree)"
mkdir -p "$worktree_repo/.coding-agent" "$worktree_repo/.claude"
printf 'note\n' >"$worktree_repo/.coding-agent/note.txt"
printf '{"permissions":{}}\n' >"$worktree_repo/.claude/settings.local.json"
worktree_path="$(cd "$worktree_repo" && "$SCRIPT" --use-worktrees feature/worktree --print-path)"
[ -d "$worktree_path/.git" ] || [ -f "$worktree_path/.git" ] || { printf 'expected linked worktree\n' >&2; exit 1; }
assert_file_contains "$worktree_repo/.repo.yml" 'use_worktrees: true' 'explicit worktree mode writes config'
assert_file_contains "$worktree_path/.coding-agent/note.txt" 'note' 'worktree mode copies .coding-agent'
assert_file_contains "$worktree_path/.claude/settings.local.json" 'permissions' 'worktree mode copies Claude local settings'

branch_repo="$(create_repo branch)"
branch_path="$(cd "$branch_repo" && "$SCRIPT" --no-worktrees feature/branch --print-path)"
[ "$branch_path" = "$branch_repo" ] || { printf 'expected repo root path, got %s\n' "$branch_path" >&2; exit 1; }
[ "$(git -C "$branch_repo" branch --show-current)" = 'feature/branch' ] || { printf 'expected feature/branch checkout\n' >&2; exit 1; }
assert_file_contains "$branch_repo/.repo.yml" 'use_worktrees: false' 'explicit branch mode writes config'

noninteractive_repo="$(create_repo noninteractive)"
noninteractive_path="$(cd "$noninteractive_repo" && "$SCRIPT" feature/default --print-path 2>"$TMPROOT/noninteractive.err")"
[ "$noninteractive_path" = "$noninteractive_repo" ] || { printf 'expected in-memory branch mode path\n' >&2; exit 1; }
[ "$(git -C "$noninteractive_repo" branch --show-current)" = 'feature/default' ] || { printf 'expected feature/default checkout\n' >&2; exit 1; }
assert_no_file "$noninteractive_repo/.repo.yml" 'noninteractive default does not write config'
assert_file_contains "$TMPROOT/noninteractive.err" 'No .repo.yml found; using branch mode for this run.' 'noninteractive default explains in-memory branch mode'

json_repo="$(create_repo json)"
json="$(cd "$json_repo" && "$SCRIPT" --no-worktrees feature/json --json)"
printf '%s\n' "$json" | jq -e '.mode == "branch" and .branch == "feature/json" and .path != ""' >/dev/null
printf 'PASS  repo-start JSON includes mode branch path\n'

dirty_repo="$(create_repo dirty)"
printf 'dirty\n' >"$dirty_repo/dirty.txt"
if (cd "$dirty_repo" && "$SCRIPT" --no-worktrees feature/dirty) >/"$TMPROOT/dirty.out" 2>"$TMPROOT/dirty.err"; then
  printf 'expected dirty branch mode to fail\n' >&2
  exit 1
fi
assert_file_contains "$TMPROOT/dirty.err" 'working tree has uncommitted changes' 'branch mode rejects dirty tree'

printf 'PASS  repo-start regression test\n'
```

- [ ] **Step 3: Run red test**

Run:

```bash
bash roles/common/files/bin/repo-start.test
```

Expected: exit 2 with `repo-start is not executable` because the helper does not exist yet.

- [ ] **Step 4: Commit red test**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Add repo-start migration tests" roles/common/files/bin/repo-start.test docs/superpowers/specs/2026-05-02-repo-lifecycle-config-design.md
```

Expected: commit created.

## Task 2: Implement `repo-start`

**Files:**
- Create: `roles/common/files/bin/repo-lib.sh`
- Create: `roles/common/files/bin/repo-start`
- Modify: `roles/common/files/bin/repo-start.test`

- [ ] **Step 1: Create `repo-lib.sh` from existing worktree library**

Copy the useful bodies from `worktree-lib.sh`, keeping the existing behavior but using the new file name. Add these new functions:

```bash
_repo_config_path() { printf '%s/.repo.yml\n' "$1"; }

_repo_read_mode() {
  local repo_root="$1" value
  [ -f "$(_repo_config_path "$repo_root")" ] || return 1
  value="$(yq -r '.use_worktrees // ""' "$(_repo_config_path "$repo_root")")"
  case "$value" in
    true) printf 'worktree\n' ;;
    false) printf 'branch\n' ;;
    '') return 1 ;;
    *) printf 'Error: .repo.yml use_worktrees must be true or false\n' >&2; return 2 ;;
  esac
}

_repo_write_mode() {
  local repo_root="$1" mode="$2" value file
  file="$(_repo_config_path "$repo_root")"
  case "$mode" in
    worktree) value=true ;;
    branch) value=false ;;
    *) printf 'Error: invalid repo mode: %s\n' "$mode" >&2; return 1 ;;
  esac
  if [ -f "$file" ]; then
    yq -i ".use_worktrees = $value" "$file"
  else
    printf 'use_worktrees: %s\n' "$value" >"$file"
  fi
}
```

- [ ] **Step 2: Create `repo-start` implementation**

Start from `worktree-start`, then add config mode parsing. Required dispatch shape:

```bash
case "$mode" in
  worktree) repo_start_worktree ;;
  branch) repo_start_branch ;;
esac
```

Branch mode implementation must include:

```bash
repo_start_branch() {
  if [ "$path_explicit" = true ] || [ -n "$path" ]; then
    printf 'Error: branch mode does not accept a path\n' >&2
    return 1
  fi
  if [ -n "$(git -C "$repo_root" status --porcelain)" ]; then
    printf 'Error: working tree has uncommitted changes\n' >&2
    return 1
  fi
  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo_root" checkout -q "$branch"
    status=existing
  else
    git -C "$repo_root" checkout -q -b "$branch" "$start_point"
    status=created
  fi
  path="$repo_root"
}
```

Noninteractive missing config behavior must print the exact warning to stderr and not write `.repo.yml`:

```bash
printf 'No .repo.yml found; using branch mode for this run.\n' >&2
mode=branch
```

- [ ] **Step 3: Make scripts executable**

Run:

```bash
chmod +x roles/common/files/bin/repo-start
```

Expected: `test -x roles/common/files/bin/repo-start` succeeds.

- [ ] **Step 4: Run green test**

Run:

```bash
bash roles/common/files/bin/repo-start.test
```

Expected: all `repo-start` assertions pass.

- [ ] **Step 5: Commit implementation**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Add repo-start lifecycle helper" roles/common/files/bin/repo-lib.sh roles/common/files/bin/repo-start roles/common/files/bin/repo-start.test
```

Expected: commit created.

## Task 3: Add `repo-end` Red Tests And Implementation

**Files:**
- Create: `roles/common/files/bin/repo-end.test`
- Create: `roles/common/files/bin/repo-end`
- Move: `roles/macos/files/bin/cleanup-branches` to `roles/common/files/bin/cleanup-branches`
- Move: `roles/macos/files/bin/cleanup-branches.test` to `roles/common/files/bin/cleanup-branches.test`

- [ ] **Step 1: Move cleanup script into common files**

Run:

```bash
git mv roles/macos/files/bin/cleanup-branches roles/common/files/bin/cleanup-branches
git mv roles/macos/files/bin/cleanup-branches.test roles/common/files/bin/cleanup-branches.test
```

Expected: git records a rename.

- [ ] **Step 2: Write failing `repo-end` test**

Create `roles/common/files/bin/repo-end.test` with cases that use temporary bare remotes and a stubbed `cleanup-branches` in `PATH`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/repo-end"
[ -x "$SCRIPT" ] || { printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2; exit 2; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

stub_bin="$TMPROOT/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/cleanup-branches" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLEANUP_LOG"
exit "${CLEANUP_STATUS:-0}"
EOF
chmod +x "$stub_bin/cleanup-branches"
export PATH="$stub_bin:$PATH"

create_remote_repo() {
  local name="$1" origin="$TMPROOT/$name-origin.git" repo="$TMPROOT/$name-repo"
  git init -q --bare "$origin"
  git init -qb main "$repo"
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" push -q -u origin main
  printf '%s\n' "$repo"
}

branch_repo="$(create_remote_repo branch)"
git -C "$branch_repo" checkout -q -b feature/branch
printf 'branch\n' >"$branch_repo/branch.txt"
git -C "$branch_repo" add branch.txt
git -C "$branch_repo" commit -q -m branch
CLEANUP_LOG="$TMPROOT/branch-cleanup.log" CLEANUP_STATUS=0 "$SCRIPT" --print-path >/"$TMPROOT/branch.out"
grep -Fq -- '--branch feature/branch' "$TMPROOT/branch-cleanup.log"
git -C "$branch_repo" rev-parse --verify origin/main >/dev/null
grep -Fq "$branch_repo" "$TMPROOT/branch.out"
printf 'PASS  repo-end branch mode merges pushes and delegates cleanup\n'

dirty_repo="$(create_remote_repo dirty)"
git -C "$dirty_repo" checkout -q -b feature/dirty
printf 'dirty\n' >"$dirty_repo/dirty.txt"
if "$SCRIPT" >/"$TMPROOT/dirty.out" 2>"$TMPROOT/dirty.err"; then
  printf 'expected dirty repo-end to fail\n' >&2
  exit 1
fi
grep -Fq 'worktree has uncommitted changes' "$TMPROOT/dirty.err"
printf 'PASS  repo-end rejects dirty current worktree\n'

printf 'PASS  repo-end regression test\n'
```

- [ ] **Step 3: Run red test**

Run:

```bash
bash roles/common/files/bin/repo-end.test
```

Expected: exit 2 because `repo-end` does not exist.

- [ ] **Step 4: Implement `repo-end`**

Create `roles/common/files/bin/repo-end` with this control flow:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/repo-lib.sh"

print_path=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --print-path) print_path=true; shift ;;
    -h|--help) printf 'Usage: repo-end [--print-path]\n'; exit 0 ;;
    *) printf 'Error: unexpected argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

repo_root="$(_worktree_repo_root)"
branch="$(git -C "$repo_root" branch --show-current)"
[ -n "$branch" ] || { printf 'Error: detached HEAD; checkout a branch first\n' >&2; exit 1; }
main_branch="$(_worktree_main_branch)"
[ "$branch" != "$main_branch" ] || { printf 'Error: already on %s\n' "$main_branch" >&2; exit 1; }
[ -z "$(git -C "$repo_root" status --porcelain)" ] || { printf 'Error: worktree has uncommitted changes\n' >&2; exit 1; }

git -C "$repo_root" fetch -q origin || true
git -C "$repo_root" rebase --quiet "origin/$main_branch"
main_path="$(_worktree_main_path "$main_branch")"
[ -n "$main_path" ] || { printf 'Error: could not find main checkout\n' >&2; exit 1; }
[ -z "$(git -C "$main_path" status --porcelain)" ] || { printf 'Error: main checkout has uncommitted changes\n' >&2; exit 1; }
git -C "$main_path" checkout -q "$main_branch"
git -C "$main_path" merge --quiet "$branch"
git -C "$main_path" push --quiet
cleanup-branches --branch "$branch"
printf '%s\n' "$main_path"
```

- [ ] **Step 5: Run green tests**

Run:

```bash
chmod +x roles/common/files/bin/repo-end roles/common/files/bin/cleanup-branches
bash roles/common/files/bin/repo-end.test
bash roles/common/files/bin/cleanup-branches.test
```

Expected: `repo-end` tests pass and cleanup script test passes with common path.

- [ ] **Step 6: Commit repo-end work**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Add repo-end lifecycle helper" roles/common/files/bin/repo-end roles/common/files/bin/repo-end.test roles/common/files/bin/cleanup-branches roles/common/files/bin/cleanup-branches.test roles/macos/files/bin/cleanup-branches roles/macos/files/bin/cleanup-branches.test
```

Expected: commit created.

## Task 4: Migrate Shell Wrappers, Hooks, And Provisioning

**Files:**
- Modify: `roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh`
- Modify: `roles/macos/templates/dotfiles/bash_profile`
- Modify: `roles/common/templates/dotfiles/gitignore`
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/common/files/bin/codex-block-main-branch-edits`
- Modify: `roles/common/files/bin/codex-block-main-branch-edits.test`
- Modify: `roles/common/files/bin/codex-block-worktree-commands`
- Modify: `roles/common/files/bin/codex-block-worktree-commands.test`
- Create/modify: `tests/repo-lifecycle-provisioning.sh`

- [ ] **Step 1: Write provisioning red test**

Create `tests/repo-lifecycle-provisioning.sh` with literal checks:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"

require_contains() {
  local file="$1" needle="$2" name="$3"
  grep -Fq -- "$needle" "$ROOT/$file" || { printf 'FAIL  %s\n' "$name" >&2; exit 1; }
  printf 'PASS  %s\n' "$name"
}

require_not_contains() {
  local file="$1" needle="$2" name="$3"
  ! grep -Fq -- "$needle" "$ROOT/$file" || { printf 'FAIL  %s\n' "$name" >&2; exit 1; }
  printf 'PASS  %s\n' "$name"
}

require_contains roles/common/templates/dotfiles/gitignore '.repo.yml' 'global gitignore ignores .repo.yml'
require_contains roles/common/tasks/main.yml 'repo-lib.sh' 'installs repo-lib'
require_contains roles/common/tasks/main.yml 'repo-start' 'installs repo-start'
require_contains roles/common/tasks/main.yml 'repo-end' 'installs repo-end'
require_contains roles/common/tasks/main.yml 'cleanup-branches' 'installs cleanup-branches from common role'
require_not_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 'worktree-start()' 'zsh removes worktree-start wrapper'
require_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 'repo-start()' 'zsh exposes repo-start wrapper'
require_contains roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh 'rs()' 'zsh exposes rs wrapper'
require_contains roles/macos/templates/dotfiles/bash_profile 'repo-start()' 'bash exposes repo-start wrapper'
require_contains roles/common/files/bin/codex-block-main-branch-edits 'repo-start <branch>' 'main edit hook names repo-start'
require_not_contains roles/common/files/bin/codex-block-worktree-commands 'worktree-start' 'raw worktree hook stops naming worktree-start'
printf 'PASS  repo lifecycle provisioning checks\n'
```

Run:

```bash
bash tests/repo-lifecycle-provisioning.sh
```

Expected: fails before provisioning edits.

- [ ] **Step 2: Update shell wrappers**

Replace wrapper bodies with `repo-start` / `repo-end` wrappers that call `~/.local/bin/repo-start` and `~/.local/bin/repo-end` with `--print-path`, then `cd` and sync tmux. Add `rs(){ repo-start "$@"; }` and `re(){ repo-end "$@"; }`.

- [ ] **Step 3: Update helper install loop**

In `roles/common/tasks/main.yml`, change the worktree helper loop entries from public worktree scripts to:

```yaml
    - { name: repo-lib.sh, mode: '0644' }
    - { name: repo-start, mode: '0755' }
    - { name: repo-end, mode: '0755' }
    - { name: cleanup-branches, mode: '0755' }
```

Keep unrelated Codex and tmux helper entries.

- [ ] **Step 4: Update hook reason text**

Set `codex-block-main-branch-edits` reason to:

```bash
reason='File edit blocked on main. Start a non-main branch with repo-start <branch>, then retry.'
```

Set raw worktree blocker reasons so `git worktree add` says use `repo-start`, and `git worktree remove` says use `repo-end` or `cleanup-branches --branch <branch>`.

- [ ] **Step 5: Run focused tests**

Run:

```bash
bash roles/common/files/bin/codex-block-main-branch-edits.test
bash roles/common/files/bin/codex-block-worktree-commands.test
bash tests/repo-lifecycle-provisioning.sh
```

Expected: all pass.

- [ ] **Step 6: Commit provisioning and hook migration**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Provision repo lifecycle helpers" roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh roles/macos/templates/dotfiles/bash_profile roles/common/templates/dotfiles/gitignore roles/common/tasks/main.yml roles/common/files/bin/codex-block-main-branch-edits roles/common/files/bin/codex-block-main-branch-edits.test roles/common/files/bin/codex-block-worktree-commands roles/common/files/bin/codex-block-worktree-commands.test tests/repo-lifecycle-provisioning.sh
```

Expected: commit created.

## Task 5: Full Verification And PR

**Files:**
- No planned source changes unless verification exposes a bug.

- [ ] **Step 1: Run helper test suite**

Run:

```bash
bash roles/common/files/bin/repo-start.test
bash roles/common/files/bin/repo-end.test
bash roles/common/files/bin/codex-block-main-branch-edits.test
bash roles/common/files/bin/codex-block-worktree-commands.test
bash roles/common/files/bin/cleanup-branches.test
```

Expected: repo lifecycle, hook, and cleanup tests pass.

- [ ] **Step 2: Run repo provisioning tests**

Run:

```bash
bash tests/repo-lifecycle-provisioning.sh
bash tests/codex-main-edit-hook-provisioning.sh
bash tests/codex-worktree-hook-provisioning.sh
```

Expected: all pass after expectations are migrated.

- [ ] **Step 3: Run broad integration checks**

Run:

```bash
bin/provision --check
```

Expected: Ansible check mode completes without task syntax errors. If local machine state causes unrelated check-mode drift, capture the exact unrelated failure and run targeted tests above.

- [ ] **Step 4: Open PR**

After verification passes, run the repository PR workflow (`create-pull-request` / `_pull-request` skill as available in this environment) without asking for another approval.

Expected: PR opened from `repo-lifecycle-config` to `main` with verification evidence.
