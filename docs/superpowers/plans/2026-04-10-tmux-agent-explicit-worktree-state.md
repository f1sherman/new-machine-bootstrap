# tmux Agent Explicit Worktree State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the active tmux pane's Claude/Codex worktree branch, dirty state, and `[wt]` marker reliably even after an in-session worktree switch that leaves the long-lived agent process rooted on the base repository.

**Architecture:** Add a new pane-scoped publisher helper, `tmux-agent-worktree`, that writes explicit `@agent_worktree_path` and `@agent_worktree_pid` tmux options for the current pane. Replace the tmux branch fragment with a new `tmux-agent-pane-status` helper that reads that explicit pane state first and falls back to the existing process argv/cwd heuristics when the explicit state is missing or stale. Integrate the publisher into the local worktree shell helpers and the managed global Claude/Codex instructions so the explicit signal is available across all provisioned environments without patching upstream Superpowers.

**Tech Stack:** bash, tmux, git, Ansible, zsh, bash, Jinja2 (macOS tmux template).

**Spec:** `docs/superpowers/specs/2026-04-10-tmux-agent-explicit-worktree-state-design.md`

**Execution note:** Any commit checkpoint in this plan requires explicit user approval at execution time. If approval has not been given, skip the commit step and continue with the remaining verification.

**File map:**
- `roles/common/files/bin/tmux-agent-worktree` — new pane-state publisher helper with `set`, `sync-current`, and `clear`.
- `roles/common/files/bin/tmux-agent-worktree.test` — isolated bash harness for the publisher helper.
- `roles/common/files/bin/tmux-agent-pane-status` — new status helper that prefers explicit pane state and falls back to heuristics.
- `roles/common/files/bin/tmux-agent-pane-status.test` — isolated bash harness covering explicit-state precedence, stale-state fallback, and heuristic behavior.
- `roles/common/tasks/main.yml` — install both helpers and extend the managed global `~/.claude/CLAUDE.md` content (which also drives `~/.codex/AGENTS.md` via symlink).
- `roles/common/templates/dotfiles/zshrc` — publish or clear pane state automatically from `worktree-start`, `worktree-merge`, `worktree-delete`, and `worktree-done`.
- `roles/macos/templates/dotfiles/bash_profile` — same shell helper integration as zsh.
- `roles/macos/templates/dotfiles/tmux.conf` — replace the branch fragment with `tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}"`.
- `roles/linux/files/dotfiles/tmux.conf` — same `status-left` change as macOS.

**Phases and human-review gates:**

1. **Phase 1** — create the two failing test harnesses and implement both helpers green. Human review gate.
2. **Phase 2** — wire the helpers into Ansible, the shell worktree helpers, the managed global Claude/Codex instructions, and both tmux configs. Provision locally and verify generated files. Human review gate.
3. **Phase 3** — reload tmux and verify explicit pane-state behavior, dirty-state rendering, and stale-state fallback live in tmux. Human review gate.

---

## Phase 1 — Helper scripts with red/green TDD

### Task 1: Create the failing test harness for `tmux-agent-worktree`

**Files:**
- Create: `roles/common/files/bin/tmux-agent-worktree.test`
- Reference: `roles/common/files/bin/tmux-git-branch.test`

- [ ] **Step 1.1: Create `roles/common/files/bin/tmux-agent-worktree.test`**

Create `roles/common/files/bin/tmux-agent-worktree.test` with exactly this content:

```bash
#!/usr/bin/env bash
# Test harness for tmux-agent-worktree. Creates isolated repos/worktrees and
# drives the helper with env-based tmux/ps fixtures, asserting pane-local state.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-agent-worktree"

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

state_file() {
  local state_dir="$1" pane_id="$2" option_name="$3"
  printf '%s/%s.%s\n' "$state_dir" "$pane_id" "$option_name"
}

read_state() {
  local state_dir="$1" pane_id="$2" option_name="$3" path
  path="$(state_file "$state_dir" "$pane_id" "$option_name")"
  [ -f "$path" ] || return 1
  cat "$path"
}

run_case() {
  local name="$1" expected_path="$2" expected_pid="$3" expected_rc="$4" command="$5"
  shift 5

  local state_dir ps_file actual_path actual_pid rc
  state_dir="$(mktemp -d "$TMPROOT/state.XXXXXX")"
  ps_file="$(mktemp "$TMPROOT/ps.XXXXXX")"
  printf '%s' "$1" > "$ps_file"
  shift

  if (
    export TMUX="${TMUX:-/tmp/fake-tmux}"
    export TMUX_PANE="%91"
    export TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir"
    export TMUX_AGENT_WORKTREE_PANE_TTY="/dev/ttys091"
    export TMUX_AGENT_WORKTREE_PS_FILE="$ps_file"
    "$SCRIPT" $command "$@"
  ); then
    rc=0
  else
    rc=$?
  fi

  actual_path="$(read_state "$state_dir" "%91" "@agent_worktree_path" 2>/dev/null || true)"
  actual_pid="$(read_state "$state_dir" "%91" "@agent_worktree_pid" 2>/dev/null || true)"

  if [ "$actual_path" = "$expected_path" ] && [ "$actual_pid" = "$expected_pid" ] && [ "$rc" -eq "$expected_rc" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      expected path: %q\n' "$expected_path"
    printf '      actual path  : %q\n' "$actual_path"
    printf '      expected pid : %q\n' "$expected_pid"
    printf '      actual pid   : %q\n' "$actual_pid"
    printf '      rc           : %s (expected %s)\n' "$rc" "$expected_rc"
  fi
}

run_without_tmux_case() {
  local name="$1" command="$2"
  shift 2
  local rc
  if "$SCRIPT" $command "$@"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      rc: %s (expected 0)\n' "$rc"
  fi
}

make_repo() {
  local dir="$1"
  git init -qb main "$dir"
  git -C "$dir" commit -q --allow-empty -m init
}

make_linked_worktree() {
  local main_repo="$1" branch="$2" dest="$3"
  git -C "$main_repo" worktree add -q -b "$branch" "$dest"
}

main_repo="$TMPROOT/main-repo"
make_repo "$main_repo"

linked_wt="$TMPROOT/linked-wt"
make_linked_worktree "$main_repo" "feature/linked" "$linked_wt"

plain_repo="$TMPROOT/plain-repo"
make_repo "$plain_repo"

non_repo="$TMPROOT/non-repo"
mkdir -p "$non_repo"

# --- Case 1: set outside tmux ---
run_without_tmux_case "set outside tmux" "set" "$linked_wt"

# --- Case 2: set with no active agent ---
run_case "set with no active agent" "" "" 0 "set" "" "$linked_wt"

# --- Case 3: set with invalid path ---
run_case "set with invalid path" "" "" 0 "set" $'9100 S+ codex codex' "/no/such/path"

# --- Case 4: set with active agent and valid worktree ---
run_case "set with active agent and valid worktree" "$linked_wt" "9100" 0 "set" $'9100 S+ codex codex' "$linked_wt"

# --- Case 5: clear removes both pane options ---
state_dir="$(mktemp -d "$TMPROOT/state-clear.XXXXXX")"
printf '%s' "$linked_wt" > "$(state_file "$state_dir" "%91" "@agent_worktree_path")"
printf '%s' "9100" > "$(state_file "$state_dir" "%91" "@agent_worktree_pid")"
if TMUX=/tmp/fake TMUX_PANE=%91 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" "$SCRIPT" clear; then
  if [ ! -e "$(state_file "$state_dir" "%91" "@agent_worktree_path")" ] && [ ! -e "$(state_file "$state_dir" "%91" "@agent_worktree_pid")" ]; then
    pass=$((pass + 1))
    printf 'PASS  clear removes both pane options\n'
  else
    fail=$((fail + 1))
    printf 'FAIL  clear removes both pane options\n'
  fi
else
  fail=$((fail + 1))
  printf 'FAIL  clear removes both pane options\n'
fi

# --- Case 6: sync-current sets state from linked worktree cwd ---
state_dir="$(mktemp -d "$TMPROOT/state-sync.XXXXXX")"
printf '%s' $'9101 S+ codex codex' > "$TMPROOT/ps.sync"
if (
  cd "$linked_wt" &&
  TMUX=/tmp/fake \
  TMUX_PANE=%91 \
  TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  TMUX_AGENT_WORKTREE_PANE_TTY="/dev/ttys091" \
  TMUX_AGENT_WORKTREE_PS_FILE="$TMPROOT/ps.sync" \
  "$SCRIPT" sync-current
); then
  :
fi
if [ "$(read_state "$state_dir" "%91" "@agent_worktree_path" 2>/dev/null || true)" = "$linked_wt" ]; then
  pass=$((pass + 1))
  printf 'PASS  sync-current sets state from linked worktree cwd\n'
else
  fail=$((fail + 1))
  printf 'FAIL  sync-current sets state from linked worktree cwd\n'
fi

# --- Case 7: sync-current clears state from non-linked cwd ---
printf '%s' "$linked_wt" > "$(state_file "$state_dir" "%91" "@agent_worktree_path")"
printf '%s' "9101" > "$(state_file "$state_dir" "%91" "@agent_worktree_pid")"
if (
  cd "$plain_repo" &&
  TMUX=/tmp/fake \
  TMUX_PANE=%91 \
  TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  TMUX_AGENT_WORKTREE_PANE_TTY="/dev/ttys091" \
  TMUX_AGENT_WORKTREE_PS_FILE="$TMPROOT/ps.sync" \
  "$SCRIPT" sync-current
); then
  :
fi
if [ ! -e "$(state_file "$state_dir" "%91" "@agent_worktree_path")" ] && [ ! -e "$(state_file "$state_dir" "%91" "@agent_worktree_pid")" ]; then
  pass=$((pass + 1))
  printf 'PASS  sync-current clears state from non-linked cwd\n'
else
  fail=$((fail + 1))
  printf 'FAIL  sync-current clears state from non-linked cwd\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 1.2: Make the harness executable**

Run:
```bash
chmod +x roles/common/files/bin/tmux-agent-worktree.test
```

- [ ] **Step 1.3: Run the harness to confirm RED**

Run:
```bash
roles/common/files/bin/tmux-agent-worktree.test
```

Expected: the harness exits non-zero with:

```text
ERROR: <repo>/roles/common/files/bin/tmux-agent-worktree is not executable (or does not exist)
```

- [ ] **Step 1.4: Optional checkpoint commit for the failing harness (user approval required)**

Run:
```bash
git add roles/common/files/bin/tmux-agent-worktree.test
git -c commit.gpgsign=false commit -m "Add tmux-agent-worktree test harness (red)"
```

### Task 2: Implement `tmux-agent-worktree`

**Files:**
- Create: `roles/common/files/bin/tmux-agent-worktree`
- Test: `roles/common/files/bin/tmux-agent-worktree.test`

- [ ] **Step 2.1: Create `roles/common/files/bin/tmux-agent-worktree`**

Create `roles/common/files/bin/tmux-agent-worktree` with exactly this content:

```bash
#!/usr/bin/env bash
# Publish pane-local tmux worktree state for the current Claude/Codex agent.
set -u

get_process_lines() {
  local pane_tty="$1"
  if [ -n "${TMUX_AGENT_WORKTREE_PS_FILE:-}" ] && [ -f "${TMUX_AGENT_WORKTREE_PS_FILE}" ]; then
    cat "${TMUX_AGENT_WORKTREE_PS_FILE}"
  elif [ -n "$pane_tty" ]; then
    ps -o pid=,stat=,comm=,args= -t "$pane_tty" 2>/dev/null
  fi
}

is_agent_process() {
  local comm="$1" args="$2"
  case "$comm" in
    claude|codex)
      return 0
      ;;
  esac
  printf '%s\n' "$args" | grep -Eq '(^|[[:space:]])([^[:space:]]*/)?(claude|codex)([[:space:]]|$)'
}

detect_agent_pid() {
  local pane_tty="$1"
  local line pid stat comm args fg_pid="" any_pid=""

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    read -r pid stat comm args <<< "$line"
    is_agent_process "${comm:-}" "${args:-}" || continue
    any_pid="$pid"
    case "$stat" in
      *+*)
        fg_pid="$pid"
        ;;
    esac
  done < <(get_process_lines "$pane_tty")

  if [ -n "$fg_pid" ]; then
    printf '%s\n' "$fg_pid"
  elif [ -n "$any_pid" ]; then
    printf '%s\n' "$any_pid"
  fi
}

pane_tty() {
  if [ -n "${TMUX_AGENT_WORKTREE_PANE_TTY:-}" ]; then
    printf '%s\n' "$TMUX_AGENT_WORKTREE_PANE_TTY"
  else
    tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null
  fi
}

state_file() {
  local pane_id="$1" option_name="$2"
  printf '%s/%s.%s\n' "$TMUX_AGENT_WORKTREE_STATE_DIR" "$pane_id" "$option_name"
}

write_pane_option() {
  local pane_id="$1" option_name="$2" value="$3"
  if [ -n "${TMUX_AGENT_WORKTREE_STATE_DIR:-}" ]; then
    mkdir -p "$TMUX_AGENT_WORKTREE_STATE_DIR"
    printf '%s' "$value" > "$(state_file "$pane_id" "$option_name")"
  else
    tmux set-option -pt "$pane_id" "$option_name" "$value" >/dev/null 2>&1
  fi
}

clear_pane_option() {
  local pane_id="$1" option_name="$2"
  if [ -n "${TMUX_AGENT_WORKTREE_STATE_DIR:-}" ]; then
    rm -f "$(state_file "$pane_id" "$option_name")"
  else
    tmux set-option -pt "$pane_id" -u "$option_name" >/dev/null 2>&1
  fi
}

is_git_worktree_path() {
  local path="$1"
  [ -d "$path" ] || return 1
  [ "$(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]
}

is_linked_worktree() {
  local path="$1" git_dir common_dir
  git_dir=$(git -C "$path" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  common_dir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$git_dir" != "$common_dir" ]
}

on_named_branch() {
  local path="$1" branch
  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  [ -n "$branch" ]
}

cmd_set() {
  local path="${1:-}" pane_id pane_pid tty
  [ -n "${TMUX:-}" ] || return 0
  [ -n "${TMUX_PANE:-}" ] || return 0
  [ -n "$path" ] || return 0
  case "$path" in
    /*) ;;
    *) return 0 ;;
  esac
  is_git_worktree_path "$path" || return 0
  pane_id="$TMUX_PANE"
  tty="$(pane_tty)"
  [ -n "$tty" ] || return 0
  pane_pid="$(detect_agent_pid "$tty")"
  [ -n "$pane_pid" ] || return 0
  write_pane_option "$pane_id" "@agent_worktree_path" "$path"
  write_pane_option "$pane_id" "@agent_worktree_pid" "$pane_pid"
}

cmd_clear() {
  [ -n "${TMUX:-}" ] || return 0
  [ -n "${TMUX_PANE:-}" ] || return 0
  clear_pane_option "$TMUX_PANE" "@agent_worktree_path"
  clear_pane_option "$TMUX_PANE" "@agent_worktree_pid"
}

cmd_sync_current() {
  [ -n "${PWD:-}" ] || return 0
  if is_git_worktree_path "$PWD" && is_linked_worktree "$PWD" && on_named_branch "$PWD"; then
    cmd_set "$PWD"
  else
    cmd_clear
  fi
}

main() {
  case "${1:-}" in
    set)
      shift
      cmd_set "${1:-}"
      ;;
    sync-current)
      cmd_sync_current
      ;;
    clear)
      cmd_clear
      ;;
    *)
      exit 0
      ;;
  esac
}

main "$@"
exit 0
```

- [ ] **Step 2.2: Make the helper executable**

Run:
```bash
chmod +x roles/common/files/bin/tmux-agent-worktree
```

- [ ] **Step 2.3: Run the harness to confirm GREEN**

Run:
```bash
roles/common/files/bin/tmux-agent-worktree.test
```

Expected output ends with:

```text
7 passed, 0 failed
```

- [ ] **Step 2.4: Optional checkpoint commit for the helper (user approval required)**

Run:
```bash
git add roles/common/files/bin/tmux-agent-worktree roles/common/files/bin/tmux-agent-worktree.test
git -c commit.gpgsign=false commit -m "Add tmux-agent-worktree pane-state helper"
```

### Task 3: Create the failing test harness for `tmux-agent-pane-status`

**Files:**
- Create: `roles/common/files/bin/tmux-agent-pane-status.test`
- Reference: `roles/common/files/bin/tmux-git-branch.test`

- [ ] **Step 3.1: Create `roles/common/files/bin/tmux-agent-pane-status.test`**

Create `roles/common/files/bin/tmux-agent-pane-status.test` with exactly this content:

```bash
#!/usr/bin/env bash
# Test harness for tmux-agent-pane-status. Builds isolated repos/worktrees and
# drives the helper with ps/cwd/state fixtures, asserting stdout and exit code.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-agent-pane-status"

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
  local name="$1" expected="$2" expected_rc="$3" pane_id="$4" pane_tty="$5" pane_path="$6" ps_body="$7"
  shift 7

  local cwd_dir state_dir ps_file actual rc
  cwd_dir="$(mktemp -d "$TMPROOT/cwd.XXXXXX")"
  state_dir="$(mktemp -d "$TMPROOT/state.XXXXXX")"
  ps_file="$(mktemp "$TMPROOT/ps.XXXXXX")"
  printf '%s' "$ps_body" > "$ps_file"

  while [ "$#" -gt 2 ]; do
    case "$1" in
      cwd)
        printf '%s' "$3" > "$cwd_dir/$2"
        shift 3
        ;;
      state)
        printf '%s' "$4" > "$state_dir/$2.$3"
        shift 4
        ;;
      *)
        printf 'ERROR: malformed fixture list for %s\n' "$name" >&2
        exit 2
        ;;
    esac
  done

  if actual=$(
    TMUX_AGENT_PANE_STATUS_PS_FILE="$ps_file" \
    TMUX_AGENT_PANE_STATUS_CWD_MAP_DIR="$cwd_dir" \
    TMUX_AGENT_PANE_STATUS_STATE_DIR="$state_dir" \
    "$SCRIPT" "$pane_id" "$pane_tty" "$pane_path"
  ); then
    rc=0
  else
    rc=$?
  fi

  if [ "$actual" = "$expected" ] && [ "$rc" -eq "$expected_rc" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$name"
    printf '      expected : %q\n' "$expected"
    printf '      actual   : %q\n' "$actual"
    printf '      rc       : %s (expected %s)\n' "$rc" "$expected_rc"
  fi
}

make_repo() {
  local dir="$1"
  git init -qb main "$dir"
  git -C "$dir" commit -q --allow-empty -m init
}

make_linked_worktree() {
  local main_repo="$1" branch="$2" dest="$3"
  git -C "$main_repo" worktree add -q -b "$branch" "$dest"
}

base_clean="$TMPROOT/base-clean"
make_repo "$base_clean"

base_dirty="$TMPROOT/base-dirty"
make_repo "$base_dirty"
echo dirty > "$base_dirty/newfile"

main_repo="$TMPROOT/main-repo"
make_repo "$main_repo"

wt_clean="$TMPROOT/wt-clean"
make_linked_worktree "$main_repo" "feature/wt-clean" "$wt_clean"

wt_dirty="$TMPROOT/wt-dirty"
make_linked_worktree "$main_repo" "feature/wt-dirty" "$wt_dirty"
echo dirty > "$wt_dirty/newfile"

detached="$TMPROOT/detached"
make_repo "$detached"
git -C "$detached" commit -q --allow-empty -m second
sha=$(git -C "$detached" rev-parse HEAD~1)
git -C "$detached" checkout -q "$sha"

non_repo="$TMPROOT/non-repo"
mkdir -p "$non_repo"

# --- Case 1: explicit pane state with matching pid overrides pane cwd ---
run_case "explicit state overrides pane cwd" \
  "(feature/wt-clean) [wt] " \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$base_dirty" \
  $'9100 S+ codex codex' \
  state "%91" "@agent_worktree_pid" "9100" \
  state "%91" "@agent_worktree_path" "$wt_clean" \
  cwd 9100 "$base_dirty"

# --- Case 2: stale pid is ignored and falls back to args/cwd ---
run_case "stale pid falls back to heuristics" \
  "(main) " \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$base_dirty" \
  $'9100 S+ codex codex' \
  state "%91" "@agent_worktree_pid" "9999" \
  state "%91" "@agent_worktree_path" "$wt_clean" \
  cwd 9100 "$base_clean"

# --- Case 3: missing explicit path is ignored and falls back to heuristics ---
run_case "missing explicit path falls back" \
  "(feature/wt-clean) [wt] " \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$base_dirty" \
  $'9100 S+ codex codex --cd '"$wt_clean" \
  state "%91" "@agent_worktree_pid" "9100" \
  state "%91" "@agent_worktree_path" "/no/such/path" \
  cwd 9100 "$base_clean"

# --- Case 4: explicit dirty linked worktree renders dirty marker and [wt] ---
run_case "explicit dirty linked worktree renders dirty marker" \
  "(*feature/wt-dirty) [wt] " \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$base_clean" \
  $'9100 S+ claude claude' \
  state "%91" "@agent_worktree_pid" "9100" \
  state "%91" "@agent_worktree_path" "$wt_dirty" \
  cwd 9100 "$base_clean"

# --- Case 5: detached HEAD explicit path renders empty ---
run_case "detached head explicit path renders empty" \
  "" \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$base_dirty" \
  $'9100 S+ codex codex' \
  state "%91" "@agent_worktree_pid" "9100" \
  state "%91" "@agent_worktree_path" "$detached" \
  cwd 9100 "$base_dirty"

# --- Case 6: no explicit state falls back to codex --cd path ---
run_case "codex --cd overrides process cwd" \
  "(*feature/wt-dirty) [wt] " \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$base_clean" \
  $'9100 S+ codex codex --cd '"$wt_dirty" \
  cwd 9100 "$base_clean"

# --- Case 7: no explicit state falls back to agent cwd ---
run_case "agent cwd fallback" \
  "(feature/wt-clean) [wt] " \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$base_clean" \
  $'9100 S+ claude claude' \
  cwd 9100 "$wt_clean"

# --- Case 8: no explicit state falls back to pane path without [wt] ---
run_case "pane path fallback omits worktree marker" \
  "(*main) " \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$base_dirty" \
  ""

# --- Case 9: nongit pane path renders empty ---
run_case "nongit pane path renders empty" \
  "" \
  0 \
  "%91" \
  "/dev/ttys091" \
  "$non_repo" \
  ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 3.2: Make the harness executable**

Run:
```bash
chmod +x roles/common/files/bin/tmux-agent-pane-status.test
```

- [ ] **Step 3.3: Run the harness to confirm RED**

Run:
```bash
roles/common/files/bin/tmux-agent-pane-status.test
```

Expected: the harness exits non-zero with:

```text
ERROR: <repo>/roles/common/files/bin/tmux-agent-pane-status is not executable (or does not exist)
```

- [ ] **Step 3.4: Optional checkpoint commit for the failing harness (user approval required)**

Run:
```bash
git add roles/common/files/bin/tmux-agent-pane-status.test
git -c commit.gpgsign=false commit -m "Add tmux-agent-pane-status test harness (red)"
```

### Task 4: Implement `tmux-agent-pane-status`

**Files:**
- Create: `roles/common/files/bin/tmux-agent-pane-status`
- Test: `roles/common/files/bin/tmux-agent-pane-status.test`
- Reference: `~/.local/bin/tmux-agent-pane-status`

- [ ] **Step 4.1: Create `roles/common/files/bin/tmux-agent-pane-status`**

Create `roles/common/files/bin/tmux-agent-pane-status` with exactly this content:

```bash
#!/usr/bin/env bash
# Print the branch fragment for the active pane. Prefer pane-local explicit
# agent worktree state, then fall back to argv/cwd heuristics, then pane cwd.
set -u

get_process_lines() {
  local pane_tty="$1"
  if [ -n "${TMUX_AGENT_PANE_STATUS_PS_FILE:-}" ] && [ -f "${TMUX_AGENT_PANE_STATUS_PS_FILE}" ]; then
    cat "${TMUX_AGENT_PANE_STATUS_PS_FILE}"
  elif [ -n "$pane_tty" ]; then
    ps -o pid=,stat=,comm=,args= -t "$pane_tty" 2>/dev/null
  fi
}

resolve_pid_cwd() {
  local pid="$1"
  if [ -n "${TMUX_AGENT_PANE_STATUS_CWD_MAP_DIR:-}" ]; then
    local file="${TMUX_AGENT_PANE_STATUS_CWD_MAP_DIR}/${pid}"
    [ -f "$file" ] || return 1
    cat "$file"
    return 0
  fi
  case "$(uname -s)" in
    Darwin)
      lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | awk '/^n/ { sub(/^n/, ""); print; exit }'
      ;;
    Linux)
      readlink "/proc/$pid/cwd" 2>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

pane_option_file() {
  local pane_id="$1" option_name="$2"
  printf '%s/%s.%s\n' "$TMUX_AGENT_PANE_STATUS_STATE_DIR" "$pane_id" "$option_name"
}

read_pane_option() {
  local pane_id="$1" option_name="$2"
  if [ -n "${TMUX_AGENT_PANE_STATUS_STATE_DIR:-}" ]; then
    local file
    file="$(pane_option_file "$pane_id" "$option_name")"
    [ -f "$file" ] || return 1
    cat "$file"
  else
    tmux show-options -pv -t "$pane_id" "$option_name" 2>/dev/null
  fi
}

extract_agent_path_from_args() {
  local args="$1" token prev=""
  for token in $args; do
    case "$prev" in
      --cd|-C)
        printf '%s\n' "$token"
        return 0
        ;;
    esac
    case "$token" in
      --cd=*)
        printf '%s\n' "${token#--cd=}"
        return 0
        ;;
      -C=*)
        printf '%s\n' "${token#-C=}"
        return 0
        ;;
    esac
    prev="$token"
  done
  return 1
}

resolve_agent_path() {
  local pid="$1" args="$2" pane_path="$3" pid_cwd="" args_path="" candidate=""
  pid_cwd="$(resolve_pid_cwd "$pid")"
  args_path="$(extract_agent_path_from_args "$args" 2>/dev/null || true)"

  if [ -n "$args_path" ]; then
    if [ -d "$args_path" ]; then
      printf '%s\n' "$args_path"
      return 0
    fi
    if [ -n "$pid_cwd" ] && [ -d "$pid_cwd/$args_path" ]; then
      candidate="$pid_cwd/$args_path"
    elif [ -n "$pane_path" ] && [ -d "$pane_path/$args_path" ]; then
      candidate="$pane_path/$args_path"
    fi
    if [ -n "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if [ -n "$pid_cwd" ] && [ -d "$pid_cwd" ]; then
    printf '%s\n' "$pid_cwd"
  fi
}

is_agent_process() {
  local comm="$1" args="$2"
  case "$comm" in
    claude|codex)
      return 0
      ;;
  esac
  printf '%s\n' "$args" | grep -Eq '(^|[[:space:]])([^[:space:]]*/)?(claude|codex)([[:space:]]|$)'
}

detect_agent_record() {
  local pane_tty="$1"
  local line pid stat comm args fg_pid="" fg_args="" any_pid="" any_args=""

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    read -r pid stat comm args <<< "$line"
    is_agent_process "${comm:-}" "${args:-}" || continue
    any_pid="$pid"
    any_args="$args"
    case "$stat" in
      *+*)
        fg_pid="$pid"
        fg_args="$args"
        ;;
    esac
  done < <(get_process_lines "$pane_tty")

  if [ -n "$fg_pid" ]; then
    printf '%s\t%s\n' "$fg_pid" "$fg_args"
  elif [ -n "$any_pid" ]; then
    printf '%s\t%s\n' "$any_pid" "$any_args"
  fi
}

is_linked_worktree() {
  local path="$1" git_dir common_dir
  git_dir=$(git -C "$path" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  common_dir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$git_dir" != "$common_dir" ]
}

branch_fragment_for_path() {
  local path="$1" include_wt="$2" branch wt_suffix=""

  [ -n "$path" ] || return 0
  [ -d "$path" ] || return 0
  if [ "$(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
    return 0
  fi

  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  [ -n "$branch" ] || return 0

  if [ "$include_wt" = "1" ] && is_linked_worktree "$path"; then
    wt_suffix=" [wt]"
  fi

  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    printf '(*%s)%s ' "$branch" "$wt_suffix"
  else
    printf '(%s)%s ' "$branch" "$wt_suffix"
  fi
}

main() {
  local pane_id="${1:-}" pane_tty="${2:-}" pane_path="${3:-}"
  local agent_record="" agent_pid="" agent_args=""
  local explicit_pid="" explicit_path="" heuristic_path=""

  if [ -n "$pane_tty" ]; then
    agent_record="$(detect_agent_record "$pane_tty")"
    IFS=$'\t' read -r agent_pid agent_args <<< "$agent_record"
  fi

  if [ -n "$pane_id" ] && [ -n "$agent_pid" ]; then
    explicit_pid="$(read_pane_option "$pane_id" "@agent_worktree_pid" 2>/dev/null || true)"
    explicit_path="$(read_pane_option "$pane_id" "@agent_worktree_path" 2>/dev/null || true)"
    if [ -n "$explicit_pid" ] && [ "$explicit_pid" = "$agent_pid" ] && [ -n "$explicit_path" ] && [ -d "$explicit_path" ]; then
      branch_fragment_for_path "$explicit_path" 1
      exit 0
    fi
  fi

  if [ -n "$agent_pid" ]; then
    heuristic_path="$(resolve_agent_path "$agent_pid" "$agent_args" "$pane_path")"
    if [ -n "$heuristic_path" ] && [ -d "$heuristic_path" ]; then
      branch_fragment_for_path "$heuristic_path" 1
      exit 0
    fi
  fi

  branch_fragment_for_path "$pane_path" 0
}

main "$@"
exit 0
```

- [ ] **Step 4.2: Make the helper executable**

Run:
```bash
chmod +x roles/common/files/bin/tmux-agent-pane-status
```

- [ ] **Step 4.3: Run the harness to confirm GREEN**

Run:
```bash
roles/common/files/bin/tmux-agent-pane-status.test
```

Expected output ends with:

```text
9 passed, 0 failed
```

- [ ] **Step 4.4: Run the existing branch-helper regressions**

Run:
```bash
bash roles/common/files/bin/tmux-git-branch.test
bash roles/common/files/bin/cc-git-branch-dirty.test
```

Expected:
- `tmux-git-branch.test` ends with `9 passed, 0 failed`
- `cc-git-branch-dirty.test` ends with `9 passed, 0 failed`

- [ ] **Step 4.5: Optional checkpoint commit for the helper (user approval required)**

Run:
```bash
git add roles/common/files/bin/tmux-agent-pane-status roles/common/files/bin/tmux-agent-pane-status.test
git -c commit.gpgsign=false commit -m "Add explicit-state-aware tmux agent status helper"
```

### Phase 1 Human Review Gate

**Stop here.** Present:
- the two new helpers
- both new test harnesses
- all four test results
- whether explicit pane state, stale-state fallback, and heuristic fallback matched the spec

Wait for approval before starting Phase 2.

## Phase 2 — Wire the helpers into tmux, shell helpers, and global instructions

### Task 5: Install both helpers and update tmux to call `tmux-agent-pane-status`

**Files:**
- Modify: `roles/common/tasks/main.yml:200-240`
- Modify: `roles/macos/templates/dotfiles/tmux.conf:51-56`
- Modify: `roles/linux/files/dotfiles/tmux.conf:49-54`

- [ ] **Step 5.1: Add install tasks for both new helpers**

In `roles/common/tasks/main.yml`, insert these two tasks immediately after the existing `Install tmux-git-branch script` task:

```yaml
- name: Install tmux-agent-worktree script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-agent-worktree'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-agent-worktree'
    mode: 0755

- name: Install tmux-agent-pane-status script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-agent-pane-status'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-agent-pane-status'
    mode: 0755
```

- [ ] **Step 5.2: Update the macOS tmux status line**

Replace line 55 in `roles/macos/templates/dotfiles/tmux.conf` with:

```tmux
set -g status-left '#[fg=yellow]#($HOME/.local/bin/tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

- [ ] **Step 5.3: Update the Linux tmux status line**

Replace line 53 in `roles/linux/files/dotfiles/tmux.conf` with:

```tmux
set -g status-left '#[fg=yellow]#($HOME/.local/bin/tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}")#[fg=cyan]#{b:pane_current_path} #[fg=white]#($HOME/.local/bin/tmux-host-tag)'
```

- [ ] **Step 5.4: Re-run all helper tests**

Run:
```bash
bash roles/common/files/bin/tmux-agent-worktree.test
bash roles/common/files/bin/tmux-agent-pane-status.test
bash roles/common/files/bin/tmux-git-branch.test
bash roles/common/files/bin/cc-git-branch-dirty.test
```

Expected:
- `tmux-agent-worktree.test` ends with `7 passed, 0 failed`
- `tmux-agent-pane-status.test` ends with `9 passed, 0 failed`
- `tmux-git-branch.test` ends with `9 passed, 0 failed`
- `cc-git-branch-dirty.test` ends with `9 passed, 0 failed`

- [ ] **Step 5.5: Optional checkpoint commit for the tmux wiring (user approval required)**

Run:
```bash
git add roles/common/tasks/main.yml roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git -c commit.gpgsign=false commit -m "Wire tmux status to explicit agent worktree state"
```

### Task 6: Publish/clear pane state from the local worktree shell helpers

**Files:**
- Modify: `roles/common/templates/dotfiles/zshrc:104-382`
- Modify: `roles/macos/templates/dotfiles/bash_profile:180-427`

- [ ] **Step 6.1: Add a small shell helper in `zshrc`**

Insert this function immediately after `_worktree_cmd()` in `roles/common/templates/dotfiles/zshrc`:

```bash
_worktree_sync_tmux_state() {
  if command -v tmux-agent-worktree >/dev/null 2>&1; then
    tmux-agent-worktree sync-current >/dev/null 2>&1 || true
  fi
}
```

- [ ] **Step 6.2: Publish state from `worktree-start` in `zshrc`**

After `cd "$path"` and before the two `echo` lines in `worktree-start`, insert:

```bash
  _worktree_sync_tmux_state
```

- [ ] **Step 6.3: Clear or reset state after returning to the main worktree in `zshrc`**

After each `cd "$main_path"` in these functions, insert `_worktree_sync_tmux_state` on its own line:

- `worktree-merge`
- `worktree-delete`
- `worktree-done`

The resulting snippets should look like:

```bash
  cd "$main_path"
  _worktree_sync_tmux_state
  echo "==> Merged ${current_branch} into ${main_branch}:"
```

and:

```bash
  cd "$main_path"
  _worktree_sync_tmux_state
  "$(_worktree_cmd git)" -C "$main_path" worktree remove "$current_path"
```

- [ ] **Step 6.4: Mirror the same helper in `bash_profile`**

Insert the same `_worktree_sync_tmux_state()` function after `_worktree_cmd()` in `roles/macos/templates/dotfiles/bash_profile`, then make the same `_worktree_sync_tmux_state` insertions after:

- `cd "$path"` in `worktree-start`
- `cd "$main_path"` in `worktree-merge`
- `cd "$main_path"` in `worktree-delete`
- `cd "$main_path"` in `worktree-done`

- [ ] **Step 6.5: Provision and verify the generated shell files**

Run:
```bash
bin/provision
rg -n "_worktree_sync_tmux_state|tmux-agent-worktree sync-current" "$HOME/.zshrc" "$HOME/.bash_profile"
```

Expected:
- `bin/provision` exits 0 and `PLAY RECAP` shows `failed=0`
- `rg` shows the helper function and the four call sites in both installed shell files

- [ ] **Step 6.6: Optional checkpoint commit for the shell integration (user approval required)**

Run:
```bash
git add roles/common/templates/dotfiles/zshrc roles/macos/templates/dotfiles/bash_profile
git -c commit.gpgsign=false commit -m "Publish tmux worktree state from shell helpers"
```

### Task 7: Extend the managed global Claude/Codex instructions

**Files:**
- Modify: `roles/common/tasks/main.yml:248-299`

- [ ] **Step 7.1: Add a tmux worktree state section to the managed CLAUDE.md content**

In the inline `content: |` block for `Create ~/.claude/CLAUDE.md file`, insert this section after `## Bias Toward Action` and before `## Code Comments`:

```markdown
      ## tmux Worktree State

      When you are running inside tmux and you create or switch to a git worktree:
      - Prefer `worktree-start` when it is available. It handles local worktree setup and publishes tmux pane state.
      - If you create or switch to a worktree by some other means, immediately run `tmux-agent-worktree set <absolute-path>`.
      - If you return from that worktree to the base repository, run `tmux-agent-worktree clear`.
```

This will automatically apply to Codex too because `~/.codex/AGENTS.md` is a symlink to `~/.claude/CLAUDE.md`.

- [ ] **Step 7.2: Provision and verify the installed global instructions**

Run:
```bash
bin/provision
rg -n "tmux Worktree State|tmux-agent-worktree|worktree-start" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
```

Expected:
- `bin/provision` exits 0 and `PLAY RECAP` shows `failed=0`
- `rg` shows the new section in `~/.claude/CLAUDE.md`
- `rg` also matches through `~/.codex/AGENTS.md`

- [ ] **Step 7.3: Optional checkpoint commit for the global instruction update (user approval required)**

Run:
```bash
git add roles/common/tasks/main.yml
git -c commit.gpgsign=false commit -m "Teach Claude and Codex to publish tmux worktree state"
```

### Phase 2 Human Review Gate

**Stop here.** Present:
- all changed repo files
- the four automated test results
- `bin/provision` results
- confirmation that generated `~/.tmux.conf`, `~/.zshrc`, `~/.bash_profile`, `~/.claude/CLAUDE.md`, and `~/.codex/AGENTS.md` contain the expected wiring

Wait for approval before starting Phase 3.

## Phase 3 — Live tmux verification

### Task 8: Verify explicit pane-state behavior in the current tmux session

**Files:**
- No file changes in this task

- [ ] **Step 8.1: Reload tmux**

Run:
```bash
tmux source-file "$HOME/.tmux.conf"
```

Expected: exit 0 with no output.

- [ ] **Step 8.2: Verify base-pane fallback before explicit state is set**

In the current Codex pane, run:

```bash
tmux display-message -p '#($HOME/.local/bin/tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}")'
```

Expected before explicit state is set: the branch fragment still reflects the base repository branch, for example `(main) ` or `(*main) `.

- [ ] **Step 8.3: Publish explicit pane state for the current worktree**

From the tmux pane running Codex on the base repo, run:

```bash
tmux-agent-worktree set /Users/brian/projects/new-machine-bootstrap/.worktrees/superpowers-worktree-process-tree
```

Then inspect the branch fragment:

```bash
tmux display-message -p '#($HOME/.local/bin/tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}")'
```

Expected:

```text
(investigate/superpowers-worktree-process-tree) [wt] 
```

The cyan directory segment in the live status bar should still show `new-machine-bootstrap`, because `pane_current_path` has not changed.

- [ ] **Step 8.4: Verify dirty-state rendering from explicit pane state**

Run:

```bash
touch /Users/brian/projects/new-machine-bootstrap/.worktrees/superpowers-worktree-process-tree/tmux-agent-worktree-dirty.txt
tmux display-message -p '#($HOME/.local/bin/tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}")'
```

Expected:

```text
(*investigate/superpowers-worktree-process-tree) [wt] 
```

Then clean up:

```bash
rm /Users/brian/projects/new-machine-bootstrap/.worktrees/superpowers-worktree-process-tree/tmux-agent-worktree-dirty.txt
```

- [ ] **Step 8.5: Verify clear returns to heuristic/base behavior**

Run:

```bash
tmux-agent-worktree clear
tmux display-message -p '#($HOME/.local/bin/tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}")'
```

Expected: the branch fragment falls back to the base repo view, for example `(main) ` or `(*main) `, with no `[wt]`.

- [ ] **Step 8.6: Verify stale pane state is ignored**

Run:

```bash
tmux set-option -pt "$TMUX_PANE" @agent_worktree_pid 999999
tmux set-option -pt "$TMUX_PANE" @agent_worktree_path /Users/brian/projects/new-machine-bootstrap/.worktrees/superpowers-worktree-process-tree
tmux display-message -p '#($HOME/.local/bin/tmux-agent-pane-status "#{pane_id}" "#{pane_tty}" "#{pane_current_path}")'
tmux-agent-worktree clear
```

Expected: because the stored pid does not match the active pane agent pid, the branch fragment ignores the explicit state and falls back to the base repo view.

### Phase 3 Human Review Gate

**Stop here.** Present:
- whether the live explicit-state publish worked
- whether `[wt]` and dirty rendering matched the spec
- whether clear returned the pane to heuristic/base behavior
- whether stale pid state was ignored cleanly

Wait for approval before any merge, PR, or cleanup workflow.

## Plan self-review

- **Spec coverage:** the plan covers all spec sections: pane-local tmux state, the publisher helper, the status helper, shell-helper integration, tmux wiring, global instruction updates, and live verification.
- **Placeholder scan:** no `TODO`, `TBD`, or “implement later” placeholders remain; each code-changing step contains concrete code or an exact replacement snippet.
- **Type consistency:** the same names are used throughout: `tmux-agent-worktree`, `tmux-agent-pane-status`, `@agent_worktree_path`, `@agent_worktree_pid`, `sync-current`, `set`, and `clear`.
