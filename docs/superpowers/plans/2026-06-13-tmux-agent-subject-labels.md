# Tmux Agent Subject Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit task-subject labels for Claude Code and Codex tmux panes, while routing repo-start/repo-end label updates through the same shared state path.

**Architecture:** Add a shared `tmux-agent-state` helper that owns pane-local agent state and renders both pane-border (`@pane-label`) and window (`@window-label`) caches. Keep `tmux-agent-worktree` as the public worktree API, add `tmux-agent-subject` as the subject API, and add reminder hooks for Claude Skill use and Codex prompt use. Session-start hooks bind `@agent_kind`; repo-end clears worktree state but retains subject invisibly as stale.

**Tech Stack:** Bash helpers, jq hook parsing, tmux pane-local options, Ansible provisioning tasks, existing shell/Ruby integration test harnesses.

---

## File Structure

- Create `roles/common/files/bin/tmux-agent-state`: shared pane-local state and label renderer.
- Create `roles/common/files/bin/tmux-agent-subject`: small user-facing wrapper around `tmux-agent-state`.
- Modify `roles/common/files/bin/tmux-agent-worktree`: delegate final rendering and worktree clearing semantics to `tmux-agent-state`.
- Modify `roles/common/files/bin/tmux-window-label`: prefer cached `@window-label` before `@pane-label` and fallback behavior.
- Modify `roles/common/files/bin/tmux-claude-session-start`: bind `@agent_kind=claude` through the shared helper.
- Modify `roles/common/files/bin/codex-bind-tmux-pane`: bind `@agent_kind=codex` through the shared helper.
- Create `roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh`: Claude `PostToolUse` Skill reminder hook.
- Create `roles/common/files/bin/codex-remind-agent-subject-on-prompt`: Codex `UserPromptSubmit` reminder hook.
- Modify `roles/common/files/claude/CLAUDE.md.d/00-base.md`: add model-visible subject helper instruction shared by Claude and Codex.
- Modify `roles/common/tasks/main.yml`: install helpers and register Claude/Codex hooks.
- Modify `roles/common/files/bin/codex-trust-managed-hooks`: trust the new Codex prompt hook.
- Add/extend tests:
  - `tests/tmux-agent-state.sh`
  - `tests/tmux-label-contract.sh`
  - `tests/tmux-claude-session-start.sh`
  - `tests/codex-bind-tmux-pane.sh`
  - `tests/agent-subject-hooks.sh`
  - `tests/repo-policy.sh`

---

### Task 1: Shared Agent State Helper

**Files:**
- Create: `roles/common/files/bin/tmux-agent-state`
- Create: `roles/common/files/bin/tmux-agent-subject`
- Create: `tests/tmux-agent-state.sh`
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 1: Write the failing test for subject state and label composition**

Create `tests/tmux-agent-state.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
STATE="$BIN_DIR/tmux-agent-state"
SUBJECT="$BIN_DIR/tmux-agent-subject"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  [[ -f "$path" ]] || fail_case "$name" "missing file: $path"
  grep -Fq -- "$needle" "$path" || fail_case "$name" "missing '$needle' in $path"
  pass_case "$name"
}

assert_no_file() {
  local path="$1" name="$2"
  [[ ! -e "$path" ]] || fail_case "$name" "expected absent: $path"
  pass_case "$name"
}

stub_bin="$TMPROOT/bin"
state_dir="$TMPROOT/state"
mkdir -p "$stub_bin" "$state_dir"

cat >"$stub_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_AGENT_STATE_WINDOW_LOG"
STUB
chmod +x "$stub_bin/tmux-window-label"

cat >"$stub_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_AGENT_STATE_TITLE_LOG"
STUB
chmod +x "$stub_bin/tmux-remote-title"

export TMUX=1
export TMUX_PANE="%1"
export TMUX_AGENT_STATE_DIR="$state_dir"
export TMUX_AGENT_STATE_WINDOW_LOG="$TMPROOT/window.log"
export TMUX_AGENT_STATE_TITLE_LOG="$TMPROOT/title.log"
export PATH="$stub_bin:$PATH"

"$STATE" set-kind codex
"$SUBJECT" set "tmux subject labels"

assert_file_contains "$state_dir/%1.@agent_kind" "codex" "set-kind stores agent kind"
assert_file_contains "$state_dir/%1.@agent_subject" "tmux subject labels" "subject wrapper stores subject"
assert_no_file "$state_dir/%1.@agent_subject_stale" "setting subject clears stale flag"
assert_file_contains "$state_dir/%1.@window-label" "codex: tmux subject labels" "subject renders codex window label"
assert_file_contains "$TMPROOT/window.log" "%1" "subject refresh invokes tmux-window-label"

"$STATE" mark-subject-stale
assert_file_contains "$state_dir/%1.@agent_subject_stale" "1" "mark-subject-stale records invisible stale state"
assert_file_contains "$state_dir/%1.@window-label" "codex: tmux subject labels" "stale subject does not change rendered window label"

"$SUBJECT" clear
assert_no_file "$state_dir/%1.@agent_subject" "subject clear removes subject"
assert_no_file "$state_dir/%1.@agent_subject_stale" "subject clear removes stale flag"

printf 'tmux-agent-state checks complete\n'
```

- [ ] **Step 2: Run the state test and verify it fails**

Run: `bash tests/tmux-agent-state.sh`

Expected: exit code `127` or `1`, with a failure showing `tmux-agent-state` or `tmux-agent-subject` is missing.

- [ ] **Step 3: Implement `tmux-agent-state`**

Create `roles/common/files/bin/tmux-agent-state`:

```bash
#!/usr/bin/env bash
set -euo pipefail

pane_id() {
  printf '%s\n' "${TMUX_PANE:-}"
}

state_file() {
  printf '%s/%s.%s\n' "$TMUX_AGENT_STATE_DIR" "$1" "$2"
}

set_pane_option() {
  local pane="$1" key="$2" value="$3"
  if [[ -n "${TMUX_AGENT_STATE_DIR:-}" ]]; then
    mkdir -p "$TMUX_AGENT_STATE_DIR"
    printf '%s' "$value" >"$(state_file "$pane" "$key")"
  else
    tmux set-option -pt "$pane" "$key" "$value" >/dev/null 2>&1 || true
  fi
}

clear_pane_option() {
  local pane="$1" key="$2"
  if [[ -n "${TMUX_AGENT_STATE_DIR:-}" ]]; then
    rm -f "$(state_file "$pane" "$key")"
  else
    tmux set-option -pt "$pane" -u "$key" >/dev/null 2>&1 || true
  fi
}

get_pane_option() {
  local pane="$1" key="$2"
  if [[ -n "${TMUX_AGENT_STATE_DIR:-}" ]]; then
    [[ -f "$(state_file "$pane" "$key")" ]] || return 1
    cat "$(state_file "$pane" "$key")"
  else
    tmux show-options -qv -p -t "$pane" "$key" 2>/dev/null
  fi
}

sanitize_subject() {
  printf '%s' "$*" \
    | tr '\r\n\t' '   ' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' \
    | cut -c 1-80
}

detect_path_label() {
  local pane="$1" path label
  path="$(get_pane_option "$pane" @agent_worktree_path 2>/dev/null || true)"
  if [[ -n "$path" && -x "${TMUX_AGENT_STATE_LABEL_FORMAT_BIN:-}" ]]; then
    label="$("${TMUX_AGENT_STATE_LABEL_FORMAT_BIN}" local "$path" 2>/dev/null || true)"
    [[ -n "$label" ]] && { printf '%s\n' "$label"; return 0; }
  fi
  label="$(get_pane_option "$pane" @pane-label 2>/dev/null || true)"
  [[ -n "$label" ]] && printf '%s\n' "$label"
}

fallback_cwd_label() {
  local path label
  if [[ -n "${TMUX_AGENT_STATE_CURRENT_PATH:-}" ]]; then
    path="$TMUX_AGENT_STATE_CURRENT_PATH"
  else
    path="$(tmux display-message -p -t "$1" '#{pane_current_path}' 2>/dev/null || true)"
  fi
  label="${path%/}"
  label="${label##*/}"
  [[ -n "$label" ]] || label="/"
  printf '%s\n' "$label"
}

render() {
  local pane="$1" kind subject pane_label window_label
  kind="$(get_pane_option "$pane" @agent_kind 2>/dev/null || true)"
  subject="$(get_pane_option "$pane" @agent_subject 2>/dev/null || true)"
  pane_label="$(detect_path_label "$pane" 2>/dev/null || true)"
  [[ -n "$pane_label" ]] || pane_label="$(fallback_cwd_label "$pane")"

  if [[ -n "$kind" && -n "$subject" ]]; then
    window_label="${kind}: ${subject}"
  elif [[ -n "$kind" ]]; then
    window_label="${kind} ${pane_label%% | *}"
  else
    window_label="$pane_label"
  fi

  set_pane_option "$pane" @pane-label "$pane_label"
  set_pane_option "$pane" @window-label "$window_label"
}

refresh() {
  local pane="$1"
  render "$pane"
  command -v tmux-window-label >/dev/null 2>&1 && tmux-window-label "$pane" >/dev/null 2>&1 || true
  command -v tmux-remote-title >/dev/null 2>&1 && tmux-remote-title publish >/dev/null 2>&1 || true
}

require_pane() {
  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || exit 0
  pane_id
}

cmd="${1:-}"
shift || true
pane="$(require_pane)"

case "$cmd" in
  set-kind)
    case "${1:-}" in claude|codex) set_pane_option "$pane" @agent_kind "$1" ;; *) exit 0 ;; esac
    refresh "$pane"
    ;;
  set-subject)
    subject="$(sanitize_subject "$*")"
    [[ -n "$subject" ]] || exit 0
    set_pane_option "$pane" @agent_subject "$subject"
    clear_pane_option "$pane" @agent_subject_stale
    refresh "$pane"
    ;;
  clear-subject)
    clear_pane_option "$pane" @agent_subject
    clear_pane_option "$pane" @agent_subject_stale
    refresh "$pane"
    ;;
  mark-subject-stale)
    if [[ -n "$(get_pane_option "$pane" @agent_subject 2>/dev/null || true)" ]]; then
      set_pane_option "$pane" @agent_subject_stale "1"
    fi
    refresh "$pane"
    ;;
  clear-worktree)
    clear_pane_option "$pane" @agent_worktree_path
    clear_pane_option "$pane" @agent_worktree_pid
    clear_pane_option "$pane" @pane-link
    clear_pane_option "$pane" @pane-link-source
    refresh "$pane"
    ;;
  refresh)
    refresh "$pane"
    ;;
  *)
    exit 0
    ;;
esac
```

- [ ] **Step 4: Implement `tmux-agent-subject` wrapper**

Create `roles/common/files/bin/tmux-agent-subject`:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state="${TMUX_AGENT_STATE_BIN:-$script_dir/tmux-agent-state}"
[[ -x "$state" ]] || state="${HOME:-}/.local/bin/tmux-agent-state"

case "${1:-}" in
  set)
    shift
    "$state" set-subject "$@"
    ;;
  clear)
    "$state" clear-subject
    ;;
  status)
    [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || exit 0
    tmux show-options -qv -p -t "$TMUX_PANE" @agent_subject 2>/dev/null || true
    ;;
  *)
    printf 'Usage: tmux-agent-subject set <subject>|clear|status\n' >&2
    exit 2
    ;;
esac
```

- [ ] **Step 5: Make new helpers executable and install them**

Run:

```bash
chmod +x roles/common/files/bin/tmux-agent-state roles/common/files/bin/tmux-agent-subject
```

Modify the `Install tmux label helpers` loop in `roles/common/tasks/main.yml` by adding:

```yaml
    - tmux-agent-state
    - tmux-agent-subject
```

- [ ] **Step 6: Run the state test and verify it passes**

Run: `bash tests/tmux-agent-state.sh`

Expected: output includes `PASS  subject wrapper stores subject` and `tmux-agent-state checks complete`.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Add tmux agent subject state helper" \
  roles/common/files/bin/tmux-agent-state \
  roles/common/files/bin/tmux-agent-subject \
  roles/common/tasks/main.yml \
  tests/tmux-agent-state.sh
```

---

### Task 2: Worktree And Window Label Integration

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-worktree`
- Modify: `roles/common/files/bin/tmux-window-label`
- Modify: `tests/tmux-label-contract.sh`

- [ ] **Step 1: Add failing tests for `@window-label` and repo-end subject retention**

In `tests/tmux-label-contract.sh`, add assertions after the existing cached `@pane-label` window-name test:

```bash
window_label_log="$TMPROOT/window-label-priority.log"
window_label_tmux_dir="$TMPROOT/window-label-priority-bin"
mkdir -p "$window_label_tmux_dir"
cat >"$window_label_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '@4\t1\told-name\t/dev/null\t/tmp/current\tzsh\tplain\t%%4\n'
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf 'codex: tmux subject labels' ;;
      @agent_worktree_path) printf '' ;;
      @pane-label) printf '(feature/label) label-repo | host-a' ;;
    esac
    ;;
  rename-window)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    ;;
esac
STUB
chmod +x "$window_label_tmux_dir/tmux"
TMUX_WINDOW_LABEL_LOG="$window_label_log" PATH="$window_label_tmux_dir:$PATH" "$WINDOW_LABEL" "%4"
assert_file_contains "$window_label_log" "rename-window -t @4 codex: tmux subject labels" "window labels prefer @window-label over @pane-label"
```

Add assertions after the existing `repo-end tmux clearer removes cached pane label` block:

```bash
subject_state_dir="$TMPROOT/state-subject-retained"
mkdir -p "$subject_state_dir"
printf 'codex' > "$subject_state_dir/%12.@agent_kind"
printf 'tmux subject labels' > "$subject_state_dir/%12.@agent_subject"
TMUX=1 \
TMUX_PANE="%12" \
TMUX_AGENT_WORKTREE_STATE_DIR="$subject_state_dir" \
TMUX_AGENT_STATE_DIR="$subject_state_dir" \
PATH="$stub_bin:$BIN_DIR:$PATH" \
  "$AGENT_WORKTREE" clear
assert_file_contains "$subject_state_dir/%12.@agent_subject" "tmux subject labels" "repo-end tmux clearer retains agent subject"
assert_file_contains "$subject_state_dir/%12.@agent_subject_stale" "1" "repo-end tmux clearer marks subject stale"
```

- [ ] **Step 2: Run label contract test and verify it fails**

Run: `bash tests/tmux-label-contract.sh`

Expected: one failure for missing `@window-label` priority or missing stale-subject retention.

- [ ] **Step 3: Update `tmux-window-label` to prefer `@window-label`**

In `roles/common/files/bin/tmux-window-label`, before the existing `@agent_worktree_path`/`@pane-label` block, add:

```bash
if [ -z "$label" ]; then
  label="$(tmux show-options -qv -p -t "$pane_id" "@window-label" 2>/dev/null || true)"
fi
```

- [ ] **Step 4: Delegate `tmux-agent-worktree clear` rendering to state helper**

In `roles/common/files/bin/tmux-agent-worktree`, add helper functions near `refresh_window_label`:

```bash
agent_state_bin() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -x "$script_dir/tmux-agent-state" ]; then
    printf '%s\n' "$script_dir/tmux-agent-state"
  else
    printf '%s\n' "${HOME:-}/.local/bin/tmux-agent-state"
  fi
}

refresh_agent_state() {
  local state
  state="$(agent_state_bin)"
  if [ -x "$state" ]; then
    TMUX_AGENT_STATE_DIR="${TMUX_AGENT_WORKTREE_STATE_DIR:-}" "$state" refresh >/dev/null 2>&1 || true
    return 0
  fi
  refresh_window_label
  publish_title
}
```

Then replace the tail of `cmd_clear` with:

```bash
  if state="$(agent_state_bin)" && [ -x "$state" ]; then
    TMUX_AGENT_STATE_DIR="${TMUX_AGENT_WORKTREE_STATE_DIR:-}" "$state" clear-worktree >/dev/null 2>&1 || true
  else
    refresh_window_label
    publish_title
  fi
```

In `cmd_set` and `cmd_sync_current`, after writing `@pane-label` and PR link state, replace the direct `refresh_window_label`/`publish_title` calls with:

```bash
  refresh_agent_state
```

- [ ] **Step 5: Run label contract test and verify it passes**

Run: `bash tests/tmux-label-contract.sh`

Expected: all existing PASS lines plus new PASS lines for `@window-label` and stale subject retention.

- [ ] **Step 6: Commit Task 2**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Route tmux worktree labels through agent state" \
  roles/common/files/bin/tmux-agent-worktree \
  roles/common/files/bin/tmux-window-label \
  tests/tmux-label-contract.sh
```

---

### Task 3: Session Start Agent Kind Binding

**Files:**
- Modify: `roles/common/files/bin/tmux-claude-session-start`
- Modify: `roles/common/files/bin/codex-bind-tmux-pane`
- Modify: `tests/tmux-claude-session-start.sh`
- Modify: `tests/codex-bind-tmux-pane.sh`

- [ ] **Step 1: Add failing hook tests for agent kind binding**

In both hook tests' `make_stubs` functions, create a `tmux-agent-state` stub:

```bash
  cat >"$stubdir/tmux-agent-state" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/agent-state.log"
exit 0
STUB
  chmod +x "$stubdir/tmux-agent-state"
```

In both `run_hook` functions, clear the log:

```bash
  : > "$TMPROOT/agent-state.log"
```

In `tests/tmux-claude-session-start.sh`, add after Scenario A:

```bash
assert_file_contains "$TMPROOT/agent-state.log" "set-kind claude" "SessionStart binds Claude agent kind"
```

In `tests/codex-bind-tmux-pane.sh`, add after Scenario A:

```bash
assert_file_contains "$TMPROOT/agent-state.log" "set-kind codex" "SessionStart binds Codex agent kind"
```

- [ ] **Step 2: Run hook tests and verify they fail**

Run:

```bash
bash tests/tmux-claude-session-start.sh
bash tests/codex-bind-tmux-pane.sh
```

Expected: failures mentioning missing `set-kind claude` and `set-kind codex`.

- [ ] **Step 3: Bind agent kind in session-start hooks**

In `roles/common/files/bin/tmux-claude-session-start`, after the session id is stored, add:

```bash
if command -v tmux-agent-state >/dev/null 2>&1; then
  tmux-agent-state set-kind claude >/dev/null 2>&1 || true
fi
```

In `roles/common/files/bin/codex-bind-tmux-pane`, after session metadata is stored, add:

```bash
if command -v tmux-agent-state >/dev/null 2>&1; then
  tmux-agent-state set-kind codex >/dev/null 2>&1 || true
fi
```

- [ ] **Step 4: Run hook tests and verify they pass**

Run:

```bash
bash tests/tmux-claude-session-start.sh
bash tests/codex-bind-tmux-pane.sh
```

Expected: both tests complete successfully.

- [ ] **Step 5: Commit Task 3**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Bind agent kind on session start" \
  roles/common/files/bin/tmux-claude-session-start \
  roles/common/files/bin/codex-bind-tmux-pane \
  tests/tmux-claude-session-start.sh \
  tests/codex-bind-tmux-pane.sh
```

---

### Task 4: Subject Reminder Hooks

**Files:**
- Create: `roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh`
- Create: `roles/common/files/bin/codex-remind-agent-subject-on-prompt`
- Create: `tests/agent-subject-hooks.sh`
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/common/files/bin/codex-trust-managed-hooks`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`

- [ ] **Step 1: Write failing hook tests**

Create `tests/agent-subject-hooks.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CLAUDE_HOOK="$REPO_ROOT/roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh"
CODEX_HOOK="$REPO_ROOT/roles/common/files/bin/codex-remind-agent-subject-on-prompt"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_contains() {
  local haystack="$1" needle="$2" name="$3"
  [[ "$haystack" == *"$needle"* ]] || fail_case "$name" "missing '$needle' in: $haystack"
  pass_case "$name"
}

assert_empty() {
  local value="$1" name="$2"
  [[ -z "$value" ]] || fail_case "$name" "expected empty, got: $value"
  pass_case "$name"
}

make_tmux_stub() {
  local subject="$1" stale="$2" stubdir="$3"
  mkdir -p "$stubdir"
  cat >"$stubdir/tmux" <<STUB
#!/usr/bin/env bash
case "\$1" in
  show-options)
    case "\${*: -1}" in
      @agent_subject) printf '%s' "$subject" ;;
      @agent_subject_stale) printf '%s' "$stale" ;;
    esac
    ;;
esac
STUB
  chmod +x "$stubdir/tmux"
}

stub_missing="$TMPROOT/missing"
make_tmux_stub "" "" "$stub_missing"
claude_out="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_missing:$PATH" "$CLAUDE_HOOK")"
assert_contains "$claude_out" "tmux-agent-subject set" "Claude skill hook reminds when subject missing"
assert_contains "$claude_out" "superpowers:brainstorming" "Claude reminder names triggering skill"

claude_other="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"superpowers:writing-plans"}}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_missing:$PATH" "$CLAUDE_HOOK")"
assert_empty "$claude_other" "Claude hook ignores non-initiating skills"

stub_set="$TMPROOT/set"
make_tmux_stub "existing subject" "" "$stub_set"
claude_set="$(printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"superpowers:systematic-debugging"}}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_set:$PATH" "$CLAUDE_HOOK")"
assert_empty "$claude_set" "Claude hook skips when subject current"

stub_stale="$TMPROOT/stale"
make_tmux_stub "old subject" "1" "$stub_stale"
codex_out="$(printf '%s' '{"prompt":"$superpowers:systematic-debugging this failure"}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_stale:$PATH" "$CODEX_HOOK")"
assert_contains "$codex_out" "tmux-agent-subject set" "Codex prompt hook reminds when subject stale"
assert_contains "$codex_out" "systematic-debugging" "Codex reminder names triggering prompt skill"

codex_other="$(printf '%s' '{"prompt":"hello"}' | TMUX=1 TMUX_PANE=%1 PATH="$stub_missing:$PATH" "$CODEX_HOOK")"
assert_empty "$codex_other" "Codex hook ignores unrelated prompts"

printf 'agent subject hook checks complete\n'
```

- [ ] **Step 2: Run hook tests and verify they fail**

Run: `bash tests/agent-subject-hooks.sh`

Expected: failure because both hook scripts are missing.

- [ ] **Step 3: Implement Claude subject reminder hook**

Create `roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

[[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$tool_name" == "Skill" ]] || exit 0

skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
case "$skill" in
  superpowers:brainstorming|superpowers:systematic-debugging) ;;
  *) exit 0 ;;
esac

subject="$(tmux show-options -qv -p -t "$TMUX_PANE" @agent_subject 2>/dev/null || true)"
stale="$(tmux show-options -qv -p -t "$TMUX_PANE" @agent_subject_stale 2>/dev/null || true)"
[[ -z "$subject" || "$stale" == "1" ]] || exit 0

reminder='You invoked '"$skill"' in a tmux agent pane without a current subject. Before continuing, run `tmux-agent-subject set "<short subject>"` using a concise noun phrase for this task. If this pane should not keep a subject, run `tmux-agent-subject clear`.'

jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
```

- [ ] **Step 4: Implement Codex subject prompt hook**

Create `roles/common/files/bin/codex-remind-agent-subject-on-prompt`:

```bash
#!/usr/bin/env bash
set -euo pipefail

[[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null || true)"
case "$prompt" in
  *'$superpowers:brainstorming'*|*'superpowers:brainstorming'*|*'$superpowers:systematic-debugging'*|*'superpowers:systematic-debugging'*) ;;
  *) exit 0 ;;
esac

subject="$(tmux show-options -qv -p -t "$TMUX_PANE" @agent_subject 2>/dev/null || true)"
stale="$(tmux show-options -qv -p -t "$TMUX_PANE" @agent_subject_stale 2>/dev/null || true)"
[[ -z "$subject" || "$stale" == "1" ]] || exit 0

reminder='You invoked brainstorming or systematic-debugging in a tmux agent pane without a current subject. Before continuing, run `tmux-agent-subject set "<short subject>"` using a concise noun phrase for this task. If this pane should not keep a subject, run `tmux-agent-subject clear`.'

jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
```

- [ ] **Step 5: Make hooks executable and register them**

Run:

```bash
chmod +x roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh \
  roles/common/files/bin/codex-remind-agent-subject-on-prompt
```

In `roles/common/tasks/main.yml`, add `codex-remind-agent-subject-on-prompt` to the executable helper install loop near other Codex helpers:

```yaml
    - { name: codex-remind-agent-subject-on-prompt, mode: '0755' }
```

Add a Claude registration task after the existing initiation-skill main-branch reminder task:

```yaml
- name: Register PostToolUse Skill hook for agent subject reminder
  shell: |
    set -euo pipefail
    settings_file="${SETTINGS_FILE:?}"
    hook_cmd='~/.claude/hooks/remind-agent-subject-on-skill.sh'
    if [ ! -s "$settings_file" ]; then
      echo '{}' > "$settings_file"
    fi
    if jq -e --arg cmd "$hook_cmd" '
      .hooks.PostToolUse // []
      | any(.matcher == "Skill" and any(.hooks[]?; .type == "command" and .command == $cmd))
    ' "$settings_file" >/dev/null 2>&1; then
      echo "unchanged"
      exit 0
    fi
    entry="$(jq -n --arg cmd "$hook_cmd" '{matcher:"Skill",hooks:[{type:"command",command:$cmd}]}')"
    tmp_file="$(mktemp)"
    jq --argjson entry "$entry" '.hooks //= {} | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [$entry])' "$settings_file" > "$tmp_file"
    mv "$tmp_file" "$settings_file"
    echo "changed"
  args:
    executable: /bin/bash
  environment:
    SETTINGS_FILE: '{{ ansible_facts["user_dir"] }}/.claude/settings.json'
  register: agent_subject_skill_hook_result
  changed_when: agent_subject_skill_hook_result.stdout.strip() == 'changed'
```

Add a Codex registration task before `Trust managed Codex hooks`:

```yaml
- name: Merge managed Codex agent subject prompt hook into ~/.codex/hooks.json
  shell: |
    set -euo pipefail
    hooks_file="${HOOKS_FILE:?}"
    managed_command='~/.local/bin/codex-remind-agent-subject-on-prompt'
    managed_entry="$(jq -n --arg cmd "$managed_command" '{hooks:[{type:"command",command:$cmd}]}')"
    tmp_file="$(mktemp)"
    if [ ! -s "$hooks_file" ]; then
      echo '{}' > "$hooks_file"
    fi
    jq --arg cmd "$managed_command" --argjson entry "$managed_entry" '
      .hooks //= {} |
      .hooks.UserPromptSubmit = (((.hooks.UserPromptSubmit // [])
        | map(.hooks = ((.hooks // []) | map(select(.type != "command" or .command != $cmd))))
        | map(select((.hooks // []) | length > 0))) + [$entry])
    ' "$hooks_file" > "$tmp_file"
    if jq -e --slurp '.[0] == .[1]' "$hooks_file" "$tmp_file" >/dev/null; then
      rm "$tmp_file"
      echo "unchanged"
    else
      mv "$tmp_file" "$hooks_file"
      chmod 600 "$hooks_file"
      echo "changed"
    fi
  args:
    executable: /bin/bash
  environment:
    HOOKS_FILE: '{{ ansible_facts["user_dir"] }}/.codex/hooks.json'
  register: codex_agent_subject_prompt_hooks_json_result
  changed_when: codex_agent_subject_prompt_hooks_json_result.stdout.strip() == 'changed'
```

- [ ] **Step 6: Update shared agent instructions**

Add this bullet to `roles/common/files/claude/CLAUDE.md.d/00-base.md` near the tmux/repo lifecycle instructions:

```markdown
* Tmux agent subject: when invoking `superpowers:brainstorming` or `superpowers:systematic-debugging` inside tmux, run `tmux-agent-subject set "<short subject>"` if the pane has no current subject or the previous subject is stale.
```

- [ ] **Step 7: Update Codex hook trust manifest**

In `roles/common/files/bin/codex-trust-managed-hooks`, inside `managed_manifest()`, replace:

```bash
    {eventName:"sessionStart", matcher:"startup|resume", command:"~/.local/bin/codex-bind-tmux-pane", timeoutSec:5},
    {eventName:"userPromptSubmit", matcher:null, command:"~/.local/bin/codex-remind-repo-start-on-dev-prompt", timeoutSec:600}
```

with:

```bash
    {eventName:"sessionStart", matcher:"startup|resume", command:"~/.local/bin/codex-bind-tmux-pane", timeoutSec:5},
    {eventName:"userPromptSubmit", matcher:null, command:"~/.local/bin/codex-remind-repo-start-on-dev-prompt", timeoutSec:600},
    {eventName:"userPromptSubmit", matcher:null, command:"~/.local/bin/codex-remind-agent-subject-on-prompt", timeoutSec:600}
```

In `tests/repo-policy.sh`, inside `run_install_checks()`, add these assertions near the existing Codex hook assertions:

```bash
  assert_contains "$COMMON_MAIN" "codex-remind-agent-subject-on-prompt" "common installs Codex agent subject prompt hook"
  assert_contains "$COMMON_MAIN" "Merge managed Codex agent subject prompt hook into ~/.codex/hooks.json" "common provisions Codex agent subject prompt hook"
  assert_contains "$CODEX_TRUST_HOOK" "codex-remind-agent-subject-on-prompt" "Codex hook trust helper trusts agent subject prompt hook"
```

- [ ] **Step 8: Run hook tests and policy tests**

Run:

```bash
bash tests/agent-subject-hooks.sh
bash tests/repo-policy.sh
```

Expected: hook tests complete with `agent subject hook checks complete`; repo policy passes with managed helper/hook assertions updated if needed.

- [ ] **Step 9: Commit Task 4**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Remind agents to set tmux subjects" \
  roles/common/files/claude/hooks/remind-agent-subject-on-skill.sh \
  roles/common/files/bin/codex-remind-agent-subject-on-prompt \
  roles/common/files/bin/codex-trust-managed-hooks \
  roles/common/files/claude/CLAUDE.md.d/00-base.md \
  roles/common/tasks/main.yml \
  tests/agent-subject-hooks.sh \
  tests/repo-policy.sh
```

---

### Task 5: Final Verification And Provision Smoke

**Files:**
- Modify: `docs/superpowers/plans/2026-06-13-tmux-agent-subject-labels.md`

- [ ] **Step 1: Run focused test suite**

Run:

```bash
bash tests/tmux-agent-state.sh
bash tests/tmux-label-contract.sh
bash tests/tmux-claude-session-start.sh
bash tests/codex-bind-tmux-pane.sh
bash tests/agent-subject-hooks.sh
bash tests/repo-policy.sh
```

Expected: every command exits `0`.

- [ ] **Step 2: Run broader repo lifecycle and hook tests**

Run:

```bash
bash tests/repo-lifecycle.sh
bash tests/repo-end-callbacks.sh
bash tests/repo-start-callbacks.sh
bash tests/codex-hook-trust.sh
```

Expected: every command exits `0`.

- [ ] **Step 3: Run Ansible check-mode validation**

Run:

```bash
ansible-playbook playbook.yml --check
```

Expected: playbook completes without task failures. Changed tasks are acceptable in check mode for copied helper files and managed hook config.

- [ ] **Step 4: Commit plan checkbox updates if changed**

Run:

```bash
git status --short docs/superpowers/plans/2026-06-13-tmux-agent-subject-labels.md
```

If the plan file changed only by checkbox progress updates, commit it:

```bash
~/.codex/skills/_commit/commit.sh -m "Track tmux agent subject implementation progress" \
  docs/superpowers/plans/2026-06-13-tmux-agent-subject-labels.md
```

- [ ] **Step 5: Open PR**

After all verification passes, run the repository PR workflow:

```bash
create-pull-request
```

Expected: a PR is opened for branch `tmux-agent-subject-labels` with verification evidence.
