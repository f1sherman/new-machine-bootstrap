# Tmux Current Spec Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `M-f` with a tmux-native current-spec side pane that works locally and on remote tmux hosts.

**Architecture:** A `PostToolUse` hook records the current spec path on the active tmux pane after Claude or Codex edits `docs/superpowers/specs/*-design.md`. `tmux-spec-current` resolves that pane-local state, and `tmux-spec-open` opens or refreshes a read-only adjacent pane. Existing SSH forwarding remains the remote boundary.

**Tech Stack:** Bash helper scripts, tmux user options, jq hook payload parsing, Ansible install tasks, shell test harnesses.

---

## File Map

- `roles/common/files/bin/agent-current-spec-hook`: shared Claude/Codex hook helper. Reads hook JSON from stdin, detects edited design spec paths, and sets `@agent_current_spec_path` on `$TMUX_PANE`.
- `roles/common/files/bin/agent-current-spec-hook.test`: shell tests for Claude payloads, Codex patch payloads, ignored paths, multi-spec edits, and no-tmux cases.
- `roles/common/files/bin/tmux-spec-current`: resolves the current spec path from pane-local tmux state, with guarded newest-spec fallback.
- `roles/common/files/bin/tmux-spec-current.test`: shell tests for state-first resolution, fallback, no-spec errors, and stale/missing state behavior.
- `roles/common/files/bin/tmux-spec-open`: opens, reuses, refreshes, and renders the side pane.
- `roles/common/files/bin/tmux-spec-open.test`: shell tests for first split, reuse, stale pane cleanup, spec-pane invocation, missing files, and render fallback.
- `roles/common/tasks/main.yml`: installs new helpers and registers Claude/Codex hooks.
- `roles/macos/templates/dotfiles/tmux.conf`: changes `M-f` binding to `tmux-spec-open`.
- `roles/linux/files/dotfiles/tmux.conf`: same `M-f` binding change.
- `roles/common/files/claude/CLAUDE.md.d/00-base.md`: adds the manual fallback instruction for shell-generated specs; Codex receives this through the existing symlinked `AGENTS.md`.
- `roles/common/files/bin/tmux-window-bar-config.test`: pins the new `M-f` binding in both tmux config files.

## Task 1: Current Spec Hook

**Files:**
- Create: `roles/common/files/bin/agent-current-spec-hook`
- Create: `roles/common/files/bin/agent-current-spec-hook.test`

- [ ] **Step 1: Write failing hook tests**

Create `roles/common/files/bin/agent-current-spec-hook.test`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/agent-current-spec-hook"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

make_repo() {
  local repo="$1"
  git -c init.templateDir= init -q "$repo"
  git -C "$repo" commit -q --allow-empty -m init
  mkdir -p "$repo/docs/superpowers/specs" "$repo/src"
  printf '# Spec\n' > "$repo/docs/superpowers/specs/2026-05-02-demo-design.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m seed
}

install_fake_tmux() {
  local bin="$1" log="$2"
  mkdir -p "$bin"
  cat > "$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TMUX_TEST_LOG"
EOF
  chmod +x "$bin/tmux"
  : > "$log"
}

assert_log_contains() {
  local log="$1" needle="$2" name="$3"
  rg -q -F -- "$needle" "$log" || fail "$name"
  pass "$name"
}

assert_log_empty() {
  local log="$1" name="$2"
  [ ! -s "$log" ] || fail "$name"
  pass "$name"
}

repo="$TMPROOT/repo"
make_repo "$repo"
bin="$TMPROOT/bin"
log="$TMPROOT/tmux.log"
install_fake_tmux "$bin" "$log"

spec_rel='docs/superpowers/specs/2026-05-02-demo-design.md'
spec_abs="$repo/$spec_rel"

jq -n --arg path "$spec_abs" --arg cwd "$repo" '{
  hook_event_name: "PostToolUse",
  tool_name: "Write",
  cwd: $cwd,
  tool_input: {file_path: $path}
}' | PATH="$bin:$PATH" TMUX=/tmp/tmux TMUX_PANE=%21 TMUX_TEST_LOG="$log" "$SCRIPT"
assert_log_contains "$log" "set-option -p -t %21 @agent_current_spec_path $spec_abs" "Claude Write payload stores absolute spec path"

: > "$log"
jq -n --arg cwd "$repo" --arg command "*** Begin Patch
*** Update File: $spec_rel
@@
 old
*** End Patch
" '{
  hook_event_name: "PostToolUse",
  tool_name: "apply_patch",
  cwd: $cwd,
  tool_input: {command: $command}
}' | PATH="$bin:$PATH" TMUX=/tmp/tmux TMUX_PANE=%22 TMUX_TEST_LOG="$log" "$SCRIPT"
assert_log_contains "$log" "set-option -p -t %22 @agent_current_spec_path $spec_rel" "Codex apply_patch payload stores relative spec path"

: > "$log"
jq -n --arg cwd "$repo" '{cwd: $cwd, tool_input: {file_path: "src/app.rb"}}' \
  | PATH="$bin:$PATH" TMUX=/tmp/tmux TMUX_PANE=%23 TMUX_TEST_LOG="$log" "$SCRIPT"
assert_log_empty "$log" "non-spec edit is ignored"

: > "$log"
jq -n --arg cwd "$repo" --arg command "*** Begin Patch
*** Update File: docs/superpowers/specs/2026-05-02-a-design.md
*** Update File: docs/superpowers/specs/2026-05-02-b-design.md
*** End Patch
" '{cwd: $cwd, tool_input: {command: $command}}' \
  | PATH="$bin:$PATH" TMUX=/tmp/tmux TMUX_PANE=%24 TMUX_TEST_LOG="$log" "$SCRIPT"
assert_log_empty "$log" "multi-spec edit is ignored"

: > "$log"
jq -n --arg path "$spec_abs" --arg cwd "$repo" '{cwd: $cwd, tool_input: {file_path: $path}}' \
  | env -u TMUX -u TMUX_PANE PATH="$bin:$PATH" TMUX_TEST_LOG="$log" "$SCRIPT"
assert_log_empty "$log" "outside tmux is quiet"

printf 'PASS  agent-current-spec-hook test suite\n'
```

- [ ] **Step 2: Run hook tests to verify failure**

Run:

```bash
bash roles/common/files/bin/agent-current-spec-hook.test
```

Expected: fails because `roles/common/files/bin/agent-current-spec-hook` does not exist.

- [ ] **Step 3: Implement hook helper**

Create `roles/common/files/bin/agent-current-spec-hook`:

```bash
#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v tmux >/dev/null 2>&1 || exit 0
[ -n "${TMUX:-}" ] || exit 0
[ -n "${TMUX_PANE:-}" ] || exit 0

payload="$(cat)"
[ -n "$payload" ] || exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo_root" ] || exit 0

spec_pattern='(^|/)docs/superpowers/specs/[^/]+-design[.]md$'

normalize_candidate() {
  local path="$1"
  path="${path#./}"
  if [[ "$path" == "$repo_root"/* ]]; then
    printf '%s\n' "$path"
  elif [[ "$path" =~ $spec_pattern ]]; then
    printf '%s\n' "$path"
  fi
}

collect_candidates() {
  local file_path command
  file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
  [ -n "$file_path" ] && normalize_candidate "$file_path"

  command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  [ -n "$command" ] || return 0
  printf '%s\n' "$command" |
    sed -n -E 's/^\*\*\* (Add|Update|Delete) File: //p' |
    while IFS= read -r path; do
      normalize_candidate "$path"
    done
}

mapfile -t specs < <(collect_candidates | awk 'length && !seen[$0]++')

[ "${#specs[@]}" -eq 1 ] || exit 0

tmux set-option -p -t "$TMUX_PANE" @agent_current_spec_path "${specs[0]}" >/dev/null 2>&1 || true
```

- [ ] **Step 4: Run hook tests to verify pass**

Run:

```bash
bash roles/common/files/bin/agent-current-spec-hook.test
```

Expected: all `PASS`.

- [ ] **Step 5: Commit hook helper**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Add current spec hook helper" \
  roles/common/files/bin/agent-current-spec-hook \
  roles/common/files/bin/agent-current-spec-hook.test
```

## Task 2: Spec Resolver

**Files:**
- Create: `roles/common/files/bin/tmux-spec-current`
- Create: `roles/common/files/bin/tmux-spec-current.test`

- [ ] **Step 1: Write failing resolver tests**

Create `roles/common/files/bin/tmux-spec-current.test`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-spec-current"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

make_repo() {
  local repo="$1"
  git -c init.templateDir= init -q "$repo"
  git -C "$repo" commit -q --allow-empty -m init
  mkdir -p "$repo/docs/superpowers/specs"
  printf '# Old\n' > "$repo/docs/superpowers/specs/2026-05-01-old-design.md"
  printf '# New\n' > "$repo/docs/superpowers/specs/2026-05-02-new-design.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m specs
}

install_fake_tmux() {
  local bin="$1" repo="$2" option="$3"
  mkdir -p "$bin"
  cat > "$bin/tmux" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
  show-options)
    printf '%s\n' "$option"
    ;;
  display-message)
    printf '%s\n' "$repo"
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$bin/tmux"
}

assert_output() {
  local expected="$1" name="$2"; shift 2
  local actual
  actual="$("$@")" || fail "$name"
  [ "$actual" = "$expected" ] || fail "$name"
  pass "$name"
}

repo="$TMPROOT/repo"
make_repo "$repo"

bin="$TMPROOT/bin-option"
install_fake_tmux "$bin" "$repo" "$repo/docs/superpowers/specs/2026-05-02-new-design.md"
assert_output "$repo/docs/superpowers/specs/2026-05-02-new-design.md" "pane option wins" \
  env PATH="$bin:$PATH" TMUX=/tmp/tmux TMUX_PANE=%31 "$SCRIPT"

bin="$TMPROOT/bin-fallback"
install_fake_tmux "$bin" "$repo" ""
assert_output "$repo/docs/superpowers/specs/2026-05-02-new-design.md" "fallback chooses newest spec" \
  env PATH="$bin:$PATH" TMUX=/tmp/tmux TMUX_PANE=%32 "$SCRIPT"

empty_repo="$TMPROOT/empty"
git -c init.templateDir= init -q "$empty_repo"
git -C "$empty_repo" commit -q --allow-empty -m init
bin="$TMPROOT/bin-empty"
install_fake_tmux "$bin" "$empty_repo" ""
if env PATH="$bin:$PATH" TMUX=/tmp/tmux TMUX_PANE=%33 "$SCRIPT" >/tmp/tmux-spec-current.out 2>/tmp/tmux-spec-current.err; then
  fail "no spec should fail"
fi
rg -q -F "no current spec" /tmp/tmux-spec-current.err || fail "no spec error message"
pass "no spec reports clear error"

printf 'PASS  tmux-spec-current test suite\n'
```

- [ ] **Step 2: Run resolver tests to verify failure**

Run:

```bash
bash roles/common/files/bin/tmux-spec-current.test
```

Expected: fails because `tmux-spec-current` does not exist.

- [ ] **Step 3: Implement resolver**

Create `roles/common/files/bin/tmux-spec-current`:

```bash
#!/usr/bin/env bash
set -euo pipefail

tmux_bin="${TMUX_SPEC_TMUX_BIN:-tmux}"
pane="${1:-${TMUX_PANE:-}}"

[ -n "${TMUX:-}" ] || { printf 'tmux-spec-current: tmux is required\n' >&2; exit 1; }
[ -n "$pane" ] || { printf 'tmux-spec-current: pane id is required\n' >&2; exit 1; }

option="$("$tmux_bin" show-options -qv -pt "$pane" @agent_current_spec_path 2>/dev/null || true)"
if [ -n "$option" ]; then
  printf '%s\n' "$option"
  exit 0
fi

pane_path="$("$tmux_bin" display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null || true)"
[ -n "$pane_path" ] || pane_path="$PWD"

repo_root="$(git -C "$pane_path" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ]; then
  printf 'tmux-spec-current: no current spec and pane is not in a git repo\n' >&2
  exit 1
fi

spec_dir="$repo_root/docs/superpowers/specs"
if [ ! -d "$spec_dir" ]; then
  printf 'tmux-spec-current: no current spec under %s\n' "$spec_dir" >&2
  exit 1
fi

latest="$(ls -t "$spec_dir"/*-design.md 2>/dev/null | head -n 1 || true)"
if [ -z "$latest" ]; then
  printf 'tmux-spec-current: no current spec under %s\n' "$spec_dir" >&2
  exit 1
fi

printf '%s\n' "$latest"
```

- [ ] **Step 4: Run resolver tests to verify pass**

Run:

```bash
bash roles/common/files/bin/tmux-spec-current.test
```

Expected: all `PASS`.

- [ ] **Step 5: Commit resolver**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Add current spec resolver" \
  roles/common/files/bin/tmux-spec-current \
  roles/common/files/bin/tmux-spec-current.test
```

## Task 3: Spec Side Pane Opener

**Files:**
- Create: `roles/common/files/bin/tmux-spec-open`
- Create: `roles/common/files/bin/tmux-spec-open.test`

- [ ] **Step 1: Write failing opener tests**

Create `roles/common/files/bin/tmux-spec-open.test`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-spec-open"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0

state_file() { printf '%s/state/%s.%s\n' "$1" "$2" "$3"; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'FAIL  %s\nexpected: %q\nactual: %q\n' "$name" "$expected" "$actual"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'FAIL  %s\nmissing: %q\nhaystack: %q\n' "$name" "$needle" "$haystack"
  fi
}

make_fake_tmux() {
  local fake_tmux="$1"
  cat > "$fake_tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

fake_dir="${TMUX_SPEC_FAKE_DIR:?}"
mkdir -p "$fake_dir/state"
cmd="${1:?}"
shift || true

state_file() { printf '%s/state/%s.%s\n' "$fake_dir" "$1" "$2"; }
pane_exists() { grep -Fqx -- "$1" "$fake_dir/pane_ids" 2>/dev/null; }
pane_path() { awk -F $'\t' -v pane="$1" '$1 == pane {print $2; exit}' "$fake_dir/panes.tsv"; }

case "$cmd" in
  show-options)
    target=""; option=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -pt|-t) target="$2"; shift 2 ;;
        -qv|-v|-p) shift ;;
        *) option="$1"; shift ;;
      esac
    done
    [ -f "$(state_file "$target" "$option")" ] && cat "$(state_file "$target" "$option")"
    ;;
  set-option)
    target=""; unset_option=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -pt|-t) target="$2"; shift 2 ;;
        -u) unset_option=true; shift ;;
        -p|-q) shift ;;
        *) break ;;
      esac
    done
    option="${1:-}"; value="${2:-}"
    if [ "$unset_option" = true ]; then
      rm -f "$(state_file "$target" "$option")"
      printf 'unset %s %s\n' "$target" "$option" >> "$fake_dir/set_option_log"
    else
      printf '%s' "$value" > "$(state_file "$target" "$option")"
      printf 'set %s %s %s\n' "$target" "$option" "$value" >> "$fake_dir/set_option_log"
    fi
    ;;
  display-message)
    if [ "${1:-}" = "-p" ]; then
      shift
      [ "${1:-}" = "-t" ] && target="$2" && shift 2
      format="${1:-}"
      case "$format" in
        '#{pane_current_path}') pane_path "$target" ;;
        '#{pane_id}') pane_exists "$target" && printf '%s\n' "$target" ;;
      esac
    else
      printf '%s\n' "$*" > "$fake_dir/message"
    fi
    ;;
  list-panes)
    target=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        -F) shift 2 ;;
        *) shift ;;
      esac
    done
    pane_exists "$target" || exit 1
    ;;
  split-window)
    target=""; path=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        -c) path="$2"; shift 2 ;;
        -h|-d|-P) shift ;;
        -F) shift 2 ;;
        *) break ;;
      esac
    done
    num="$(cat "$fake_dir/counter")"
    printf '%s\n' $((num + 1)) > "$fake_dir/counter"
    pane="%$num"
    printf '%s\n' "$pane" >> "$fake_dir/pane_ids"
    printf '%s\t%s\n' "$pane" "$path" >> "$fake_dir/panes.tsv"
    printf '%s\t%s\t%s\n' "$target" "$path" "$*" > "$fake_dir/split_window"
    printf '%s\n' "$pane"
    ;;
  respawn-pane)
    target=""; path=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        -c) path="$2"; shift 2 ;;
        -k) shift ;;
        *) break ;;
      esac
    done
    printf '%s\t%s\t%s\n' "$target" "$path" "$*" > "$fake_dir/respawn_pane"
    ;;
  select-pane)
    [ "${1:-}" = "-t" ] || exit 1
    printf '%s\n' "$2" > "$fake_dir/select_pane"
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$fake_tmux"
}

seed_fake_tmux() {
  local fake_dir="$1" counter="$2" repo="$3"
  mkdir -p "$fake_dir/state"
  printf '%s\n' "$counter" > "$fake_dir/counter"
  printf '%s\n' "%1" > "$fake_dir/pane_ids"
  printf '%s\t%s\n' "%1" "$repo" > "$fake_dir/panes.tsv"
}

run_open() {
  local fake_dir="$1" fake_tmux="$2" pane_id="$3"
  shift 3
  TMUX=/tmp/fake TMUX_PANE="$pane_id" TMUX_SPEC_TMUX_BIN="$fake_tmux" TMUX_SPEC_FAKE_DIR="$fake_dir" "$SCRIPT" "$@"
}

repo="$TMPROOT/repo"
mkdir -p "$repo/docs/superpowers/specs"
spec="$repo/docs/superpowers/specs/2026-05-02-demo-design.md"
printf '# Demo\n\nbody\n' > "$spec"

fake="$TMPROOT/fake-tmux"
make_fake_tmux "$fake"

fake_dir="$TMPROOT/fake1"
seed_fake_tmux "$fake_dir" 40 "$repo"
run_open "$fake_dir" "$fake" "%1" --path "$spec"
assert_eq "first open stores spec pane id" "%40" "$(cat "$(state_file "$fake_dir" "%1" "@spec_pane_id")")"
assert_eq "first open focuses spec pane" "%40" "$(cat "$fake_dir/select_pane")"
assert_contains "first open split renders spec" "$(cat "$fake_dir/split_window")" "--render"

fake_dir="$TMPROOT/fake2"
seed_fake_tmux "$fake_dir" 50 "$repo"
printf '%s\n' "%44" >> "$fake_dir/pane_ids"
printf '%s\t%s\n' "%44" "$repo" >> "$fake_dir/panes.tsv"
printf '%s' "%44" > "$(state_file "$fake_dir" "%1" "@spec_pane_id")"
run_open "$fake_dir" "$fake" "%1" --path "$spec"
assert_contains "reuse respawns existing pane" "$(cat "$fake_dir/respawn_pane")" "%44"
assert_eq "reuse focuses existing pane" "%44" "$(cat "$fake_dir/select_pane")"

fake_dir="$TMPROOT/fake3"
seed_fake_tmux "$fake_dir" 60 "$repo"
printf '%s' "%99" > "$(state_file "$fake_dir" "%1" "@spec_pane_id")"
run_open "$fake_dir" "$fake" "%1" --path "$spec"
assert_eq "stale pane replaced" "%60" "$(cat "$(state_file "$fake_dir" "%1" "@spec_pane_id")")"
assert_contains "stale pane clears old option" "$(cat "$fake_dir/set_option_log")" "unset %1 @spec_pane_id"

fake_dir="$TMPROOT/fake4"
seed_fake_tmux "$fake_dir" 70 "$repo"
printf '%s\n' "%41" >> "$fake_dir/pane_ids"
printf '%s\t%s\n' "%41" "$repo" >> "$fake_dir/panes.tsv"
printf '%s' "%41" > "$(state_file "$fake_dir" "%1" "@spec_pane_id")"
printf '%s' "%1" > "$(state_file "$fake_dir" "%41" "@spec_origin_pane_id")"
run_open "$fake_dir" "$fake" "%41" --path "$spec"
assert_contains "spec pane refreshes itself" "$(cat "$fake_dir/respawn_pane")" "%41"
[ ! -f "$fake_dir/split_window" ] || { fail=$((fail + 1)); printf 'FAIL  spec pane should not split again\n'; }

fake_dir="$TMPROOT/fake5"
seed_fake_tmux "$fake_dir" 80 "$repo"
if run_open "$fake_dir" "$fake" "%1" --path "$repo/missing.md" >/tmp/tmux-spec-open.out 2>/tmp/tmux-spec-open.err; then
  fail=$((fail + 1)); printf 'FAIL  missing file unexpectedly succeeded\n'
else
  assert_contains "missing file displays message" "$(cat "$fake_dir/message")" "file not found"
fi

rendered="$(TMUX_SPEC_BAT_BIN=cat TMUX_SPEC_PAGER_BIN=cat "$SCRIPT" --render "$spec")"
assert_contains "render fallback prints file" "$rendered" "body"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run opener tests to verify failure**

Run:

```bash
bash roles/common/files/bin/tmux-spec-open.test
```

Expected: fails because `tmux-spec-open` does not exist.

- [ ] **Step 3: Implement opener**

Create `roles/common/files/bin/tmux-spec-open`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
tmux_bin="${TMUX_SPEC_TMUX_BIN:-tmux}"

quote() { printf '%q' "$1"; }

message() {
  local msg="$1"
  "$tmux_bin" display-message "$msg" >/dev/null 2>&1 || true
  printf '%s\n' "$msg" >&2
}

page_output() {
  case "${TMUX_SPEC_PAGER_BIN:-}" in
    cat) cat ;;
    "") command -v less >/dev/null 2>&1 && less -R || cat ;;
    *) "${TMUX_SPEC_PAGER_BIN}" ;;
  esac
}

render_body() {
  local path="$1"
  case "${TMUX_SPEC_BAT_BIN:-}" in
    cat) cat "$path" ;;
    "") command -v bat >/dev/null 2>&1 && bat --paging=never --style=numbers --color=always "$path" || cat "$path" ;;
    *) "${TMUX_SPEC_BAT_BIN}" --paging=never --style=numbers --color=always "$path" ;;
  esac
}

render=false
explicit_path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --render) render=true; explicit_path="${2:-}"; shift 2 ;;
    --path) explicit_path="${2:-}"; shift 2 ;;
    *) explicit_path="$1"; shift ;;
  esac
done

if [ "$render" = true ]; then
  [ -f "$explicit_path" ] || { printf 'tmux-spec-open: file not found: %s\n' "$explicit_path" >&2; exit 1; }
  render_body "$explicit_path" | page_output
  exit 0
fi

[ -n "${TMUX:-}" ] || { printf 'tmux-spec-open: tmux is required\n' >&2; exit 1; }
current_pane="${TMUX_PANE:-}"
[ -n "$current_pane" ] || { printf 'tmux-spec-open: pane id is required\n' >&2; exit 1; }

origin_pane="$("$tmux_bin" show-options -qv -pt "$current_pane" @spec_origin_pane_id 2>/dev/null || true)"
[ -n "$origin_pane" ] || origin_pane="$current_pane"

if [ -n "$explicit_path" ]; then
  spec_path="$explicit_path"
else
  if ! spec_path="$(TMUX="$TMUX" TMUX_PANE="$origin_pane" TMUX_SPEC_TMUX_BIN="$tmux_bin" "$SCRIPT_DIR/tmux-spec-current" "$origin_pane" 2>&1)"; then
    message "$spec_path"
    exit 1
  fi
fi

if [ ! -f "$spec_path" ]; then
  message "tmux-spec-open: file not found: $spec_path"
  exit 1
fi

origin_path="$("$tmux_bin" display-message -p -t "$origin_pane" '#{pane_current_path}' 2>/dev/null || true)"
[ -n "$origin_path" ] || origin_path="$PWD"

spec_pane="$("$tmux_bin" show-options -qv -pt "$origin_pane" @spec_pane_id 2>/dev/null || true)"
if [ -n "$spec_pane" ] && ! "$tmux_bin" list-panes -t "$spec_pane" -F '' >/dev/null 2>&1; then
  "$tmux_bin" set-option -pt "$origin_pane" -u @spec_pane_id >/dev/null 2>&1 || true
  spec_pane=""
fi

viewer="$(quote "$SCRIPT_DIR/tmux-spec-open") --render $(quote "$spec_path")"

if [ -n "$spec_pane" ]; then
  "$tmux_bin" respawn-pane -k -t "$spec_pane" -c "$origin_path" "$viewer"
else
  spec_pane="$("$tmux_bin" split-window -h -d -P -F '#{pane_id}' -t "$origin_pane" -c "$origin_path" "$viewer")"
fi

"$tmux_bin" set-option -pt "$origin_pane" @spec_pane_id "$spec_pane" >/dev/null 2>&1 || true
"$tmux_bin" set-option -pt "$spec_pane" @spec_origin_pane_id "$origin_pane" >/dev/null 2>&1 || true
"$tmux_bin" set-option -pt "$spec_pane" @spec_subject "$spec_path" >/dev/null 2>&1 || true
"$tmux_bin" select-pane -t "$spec_pane"
```

- [ ] **Step 4: Run opener tests to verify pass**

Run:

```bash
bash roles/common/files/bin/tmux-spec-open.test
```

Expected: all `PASS`.

- [ ] **Step 5: Commit opener**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Add current spec side pane opener" \
  roles/common/files/bin/tmux-spec-open \
  roles/common/files/bin/tmux-spec-open.test
```

## Task 4: Install Hooks, Helpers, Bindings, and Instructions

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`

- [ ] **Step 1: Write failing config assertions**

Add assertions to `roles/common/files/bin/tmux-window-bar-config.test`:

```bash
assert_contains "$file" 'bind-key -n M-f if-shell -F "$is_ssh" '\''send-keys M-f'\'' '\''run-shell -b "TMUX_PANE=#{pane_id} ~/.local/bin/tmux-spec-open"'\'''
assert_not_contains "$file" 'tmux-review-open prompt-file'
```

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: fails because both tmux configs still bind `M-f` to `tmux-review-open prompt-file`.

- [ ] **Step 2: Install helpers through Ansible**

In `roles/common/tasks/main.yml`, add the helper names to the existing installed script loops:

```yaml
    - { name: agent-current-spec-hook, mode: '0755' }
```

Add spec helpers to the tmux review helper loop:

```yaml
    - { name: tmux-spec-current, mode: '0755' }
    - { name: tmux-spec-open, mode: '0755' }
```

- [ ] **Step 3: Register Claude PostToolUse hook**

Add a task near the other Claude hook registration tasks:

```yaml
- name: Register PostToolUse hook to publish current spec path
  shell: |
    SETTINGS='{{ ansible_facts["user_dir"] }}/.claude/settings.json'
    HOOK_CMD='$HOME/.local/bin/agent-current-spec-hook'
    if [ ! -f "$SETTINGS" ]; then
      echo '{}' > "$SETTINGS"
    fi
    if jq -e '.hooks.PostToolUse // [] | map(select(.matcher == "Edit|MultiEdit|Write" and any(.hooks[]?; .command == "'"$HOOK_CMD"'"))) | length > 0' "$SETTINGS" >/dev/null 2>&1; then
      echo "already registered"
      exit 0
    fi
    HOOK_ENTRY='{"matcher":"Edit|MultiEdit|Write","hooks":[{"type":"command","command":"'"$HOOK_CMD"'"}]}'
    jq --argjson entry "$HOOK_ENTRY" '.hooks //= {} | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [$entry])' "$SETTINGS" > "${SETTINGS}.tmp" \
      && mv "${SETTINGS}.tmp" "$SETTINGS"
  args:
    executable: /bin/bash
  register: claude_current_spec_hook_result
  changed_when: "'already registered' not in claude_current_spec_hook_result.stdout"
```

- [ ] **Step 4: Register Codex PostToolUse hook**

Add a task near the other Codex `hooks.json` tasks:

```yaml
- name: Merge managed Codex current-spec hook into ~/.codex/hooks.json
  shell: |
    set -euo pipefail
    hooks_file="${HOOKS_FILE:?}"
    managed_command='~/.local/bin/agent-current-spec-hook'
    if [ -f "$hooks_file" ] && jq -e --arg cmd "$managed_command" '
      .hooks.PostToolUse // []
      | any(.matcher == "apply_patch|Edit|Write" and any(.hooks[]?; .type == "command" and .command == $cmd))
    ' "$hooks_file" >/dev/null 2>&1; then
      echo "unchanged"
      exit 0
    fi
    managed_entry="$(jq -n --arg cmd "$managed_command" '{matcher:"apply_patch|Edit|Write",hooks:[{type:"command",command:$cmd}]}')"
    tmp_file="$(mktemp)"
    if [ -f "$hooks_file" ] && [ -s "$hooks_file" ]; then
      jq --argjson entry "$managed_entry" '.hooks //= {} | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [$entry])' "$hooks_file" > "$tmp_file"
    else
      jq -n --argjson entry "$managed_entry" '{hooks:{PostToolUse:[$entry]}}' > "$tmp_file"
    fi
    mv "$tmp_file" "$hooks_file"
    chmod 600 "$hooks_file"
    echo "changed"
  args:
    executable: /bin/bash
  environment:
    HOOKS_FILE: '{{ ansible_facts["user_dir"] }}/.codex/hooks.json'
  register: codex_current_spec_hooks_json_result
  changed_when: codex_current_spec_hooks_json_result.stdout.strip() == 'changed'
```

- [ ] **Step 5: Replace `M-f` bindings**

In both tmux config files, replace:

```tmux
bind-key -n M-f if-shell -F "$is_ssh" 'send-keys M-f' 'run-shell -b "TMUX_PANE=#{pane_id} ~/.local/bin/tmux-review-open prompt-file"'
```

with:

```tmux
bind-key -n M-f if-shell -F "$is_ssh" 'send-keys M-f' 'run-shell -b "TMUX_PANE=#{pane_id} ~/.local/bin/tmux-spec-open"'
```

- [ ] **Step 6: Add fallback instruction text**

In `roles/common/files/claude/CLAUDE.md.d/00-base.md`, add this short instruction under the Superpowers spec/plan workflow section or the general agent behavior section:

```markdown
* When you create or update a Superpowers design spec through a shell script or other path that bypasses native edit hooks, publish it to the current tmux pane:
  `tmux set-option -p -t "$TMUX_PANE" @agent_current_spec_path "$spec_path"`.
```

- [ ] **Step 7: Run config assertions**

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: all `PASS`.

- [ ] **Step 8: Commit install and binding changes**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Wire current spec pane workflow" \
  roles/common/tasks/main.yml \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf \
  roles/common/files/claude/CLAUDE.md.d/00-base.md \
  roles/common/files/bin/tmux-window-bar-config.test
```

## Task 5: Verification and PR

**Files:**
- No new source files expected.

- [ ] **Step 1: Run focused tests**

Run:

```bash
bash roles/common/files/bin/agent-current-spec-hook.test
bash roles/common/files/bin/tmux-spec-current.test
bash roles/common/files/bin/tmux-spec-open.test
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: all `PASS`.

- [ ] **Step 2: Run broader script tests touched by hook/session infrastructure**

Run:

```bash
bash roles/common/files/bin/codex-bind-tmux-pane.test
bash roles/common/files/bin/tmux-claude-session-start.test
bash roles/common/files/claude/hooks/block-main-branch-edits.sh.test
bash roles/common/files/bin/codex-block-main-branch-edits.test
```

Expected: all `PASS`.

- [ ] **Step 3: Run Ansible check syntax**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
```

Expected: `playbook: playbook.yml`.

- [ ] **Step 4: Run provisioning check**

Run:

```bash
bin/provision --check
```

Expected: completes without failed tasks. If local machine state produces unrelated changes, capture the task names and decide whether they are caused by this branch.

- [ ] **Step 5: Empirically exercise tmux helper in a throwaway tmux server**

Run:

```bash
tmpdir="$(mktemp -d)"
git -C "$tmpdir" init -q
git -C "$tmpdir" commit -q --allow-empty -m init
mkdir -p "$tmpdir/docs/superpowers/specs"
printf '# Demo\n' > "$tmpdir/docs/superpowers/specs/2026-05-02-demo-design.md"
tmux -L spec-pane-test new-session -d -s spec-pane-test -c "$tmpdir" "zsh -lc 'sleep 60'"
pane="$(tmux -L spec-pane-test display-message -p -t spec-pane-test '#{pane_id}')"
tmux -L spec-pane-test set-option -pt "$pane" @agent_current_spec_path "$tmpdir/docs/superpowers/specs/2026-05-02-demo-design.md"
TMUX=/tmp/fake TMUX_PANE="$pane" TMUX_SPEC_TMUX_BIN="tmux -L spec-pane-test" roles/common/files/bin/tmux-spec-open
tmux -L spec-pane-test list-panes -t spec-pane-test -F '#{pane_id} #{pane_current_command}'
tmux -L spec-pane-test kill-session -t spec-pane-test
```

Expected: list-panes shows at least two panes before cleanup; one pane is running `less` or a shell fallback command.

- [ ] **Step 6: Ensure clean worktree**

Run:

```bash
git status --short
```

Expected: clean.

- [ ] **Step 7: Open PR**

Run the repository PR workflow:

```bash
$_pull-request
```

Expected: PR opened for `spec-tmux-spec-pane`, with verification evidence included.
