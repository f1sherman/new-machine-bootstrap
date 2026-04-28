# Patched tmux 3.6a + Hook-Failure Status Indicator + Upstream Version Guard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a locally-patched Homebrew tmux 3.6a that includes upstream commit `2a5715f` (NULL-deref fix in `window_copy_pipe_run`); fail provisioning when upstream tmux moves past 3.6a so the workaround can be retired; surface hook-script failures live in the tmux status bar via a small wrapper script and a `prefix + H` dismiss/inspect popup.

**Architecture:** A new `roles/macos/files/homebrew/tmux-patched.rb` Homebrew formula carries the upstream patch. Ansible removes vanilla tmux, installs the patched formula, and runs an upstream-version guard task that fails `bin/provision` when `brew info tmux` reports anything other than `3.6a`. A new `roles/common/files/bin/tmux-hook-run` wrapper replaces the current inline `2>>~/.local/state/tmux/hooks.log` redirect: it logs failures, sets the tmux user option `@hook-last-error` to a short message, and always exits 0. `status-right` renders a red badge driven by `@hook-last-error`. `prefix + H` opens the log in a popup and clears the badge on close.

**Tech Stack:** Ansible (community.general.homebrew, ansible.builtin.command/fail/copy/file), Homebrew custom formula (Ruby), bash (wrapper + tests), tmux 3.6a config, Jinja2 templating for macOS tmux.conf.

---

## File Structure

**New files:**
- `roles/macos/files/homebrew/tmux-patched.rb` — Homebrew formula for patched tmux 3.6a.
- `roles/common/files/bin/tmux-hook-run` — wrapper script that logs hook failures and updates `@hook-last-error`.
- `roles/common/files/bin/tmux-hook-run.test` — bash unit test for the wrapper.

**Modified files:**
- `roles/macos/tasks/install_packages.yml` — remove `tmux` from the vanilla `homebrew` list.
- `roles/macos/tasks/main.yml` — uninstall vanilla tmux if present, install patched formula, run upstream-version guard. (Single new block, sequenced before the existing `Reload tmux config` notify points so config changes layer on top of the right binary.)
- `roles/common/tasks/main.yml` — install `tmux-hook-run` script (new entry in the existing helper-script copy block; the state-directory task added in PR #120 already exists).
- `roles/macos/templates/dotfiles/tmux.conf` — switch hook lines to `tmux-hook-run`, add `status-right` indicator + `status-right-length`, add `bind H` keybind.
- `roles/linux/files/dotfiles/tmux.conf` — same edits as the macOS conf for the wrapper / status / keybind. (Linux skips the patched-formula bits.)
- `roles/common/files/bin/tmux-window-bar-config.test` — assert wrapper invocation pattern, status-right indicator, keybind, and forbid the now-replaced inline-redirect form.

---

## Task 1: Write failing tests for `tmux-hook-run` wrapper

**Files:**
- Test: `roles/common/files/bin/tmux-hook-run.test`

The wrapper is the load-bearing piece — it gates whether failures are visible in the status bar at all. Cover passing, failing, missing-binary, and truncation cases. Stub `tmux` and `date` via PATH so the test runs without a tmux server.

- [ ] **Step 1: Create the failing test file**

```bash
cat > roles/common/files/bin/tmux-hook-run.test <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/tmux-hook-run"

if [ ! -x "$SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

bindir="$TMPROOT/bin"
mkdir -p "$bindir"
tmux_log="$TMPROOT/tmux.log"
log_file="$TMPROOT/state/tmux/hooks.log"
mkdir -p "$(dirname "$log_file")"

# Stub `tmux` to record args; succeeds for set-option, errors otherwise.
cat > "$bindir/tmux" <<'EOTMUX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TMUX_HOOK_RUN_TEST_LOG"
case "${1:-}" in
  set-option) exit 0 ;;
  *) exit 1 ;;
esac
EOTMUX
chmod +x "$bindir/tmux"

# Stub `date` so timestamps are deterministic.
cat > "$bindir/date" <<'EOD'
#!/usr/bin/env bash
printf '2026-04-28T12:00:00-0500\n'
EOD
chmod +x "$bindir/date"

assert_exit_zero() {
  local label="$1"; shift
  if "$@"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s (exit %d)\n' "$label" "$?" >&2
    exit 1
  fi
}

assert_file_empty() {
  local file="$1" label="$2"
  if [ ! -s "$file" ]; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\nfile %s should be empty but contains:\n' "$label" "$file" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_grep() {
  local file="$1" pattern="$2" label="$3"
  if grep -Fq -- "$pattern" "$file"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\nmissing %q in %s:\n' "$label" "$pattern" "$file" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_no_grep() {
  local file="$1" pattern="$2" label="$3"
  if [ ! -s "$file" ] || ! grep -Fq -- "$pattern" "$file"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\nunexpectedly found %q in %s\n' "$label" "$pattern" "$file" >&2
    exit 1
  fi
}

run_wrapper() {
  PATH="$bindir:/usr/bin:/bin" \
  HOME="$TMPROOT" \
  TMUX_HOOK_RUN_TEST_LOG="$tmux_log" \
  "$SCRIPT" "$@"
}

reset_state() {
  : > "$tmux_log"
  : > "$log_file"
}

# --- Case 1: passing wrapped command ---
reset_state
cat > "$bindir/successful" <<'EOC'
#!/usr/bin/env bash
exit 0
EOC
chmod +x "$bindir/successful"
assert_exit_zero "passing command exits 0" run_wrapper successful arg1 arg2
assert_file_empty "$log_file" "passing command leaves log empty"
assert_no_grep "$tmux_log" "set-option" "passing command does not call tmux set-option"

# --- Case 2: failing wrapped command (writes stderr) ---
reset_state
cat > "$bindir/noisy_fail" <<'EOC'
#!/usr/bin/env bash
echo "boom: something broke" >&2
exit 7
EOC
chmod +x "$bindir/noisy_fail"
assert_exit_zero "failing command still exits 0" run_wrapper noisy_fail %53
assert_grep "$log_file" "exit=7" "log records exit code"
assert_grep "$log_file" "noisy_fail" "log records command name"
assert_grep "$log_file" "boom: something broke" "log records stderr"
assert_grep "$log_file" "2026-04-28T12:00:00-0500" "log records timestamp"
assert_grep "$tmux_log" "set-option -gq @hook-last-error" "tmux set-option called with @hook-last-error"
assert_grep "$tmux_log" "noisy_fail: boom: something broke" "tmux message contains short error"

# --- Case 3: failing command with no stderr ---
reset_state
cat > "$bindir/silent_fail" <<'EOC'
#!/usr/bin/env bash
exit 3
EOC
chmod +x "$bindir/silent_fail"
assert_exit_zero "silent failing command still exits 0" run_wrapper silent_fail
assert_grep "$log_file" "exit=3" "silent failure logs exit code"
assert_grep "$tmux_log" "silent_fail: exit 3" "silent failure surfaces fallback message"

# --- Case 4: missing wrapped command ---
reset_state
assert_exit_zero "missing command still exits 0" run_wrapper this-does-not-exist arg
assert_grep "$log_file" "this-does-not-exist" "missing command logged"
assert_grep "$tmux_log" "set-option -gq @hook-last-error" "missing command sets @hook-last-error"

# --- Case 5: stderr longer than 60 chars truncates ---
reset_state
long_msg="abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_extra_padding_past_sixty"
cat > "$bindir/long_stderr_fail" <<EOC
#!/usr/bin/env bash
echo "$long_msg" >&2
exit 1
EOC
chmod +x "$bindir/long_stderr_fail"
assert_exit_zero "long-stderr command still exits 0" run_wrapper long_stderr_fail
# The status-bar message stored via set-option must be at most 60 chars long.
short_line="$(grep -F 'set-option -gq @hook-last-error' "$tmux_log" | tail -n1)"
short_value="${short_line#*@hook-last-error }"
short_value="${short_value#\"}"
short_value="${short_value%\"}"
if [ "${#short_value}" -le 60 ]; then
  printf 'PASS  truncated message is %d chars (<=60)\n' "${#short_value}"
else
  printf 'FAIL  truncated message is %d chars: %q\n' "${#short_value}" "$short_value" >&2
  exit 1
fi

# --- Case 6: no args ---
reset_state
assert_exit_zero "no-args invocation exits 0" run_wrapper
assert_file_empty "$log_file" "no-args leaves log empty"
assert_no_grep "$tmux_log" "set-option" "no-args does not touch tmux"

printf '\nALL TESTS PASSED\n'
EOF
chmod +x roles/common/files/bin/tmux-hook-run.test
```

- [ ] **Step 2: Run the test to verify it fails (script does not exist yet)**

Run: `bash roles/common/files/bin/tmux-hook-run.test`
Expected: `ERROR: .../tmux-hook-run is not executable (or does not exist)` and exit 2.

- [ ] **Step 3: Commit the failing test**

```bash
git add roles/common/files/bin/tmux-hook-run.test
git commit
```

Commit subject: `Add failing tests for tmux-hook-run wrapper`. Body: brief note that the wrapper itself is implemented in the next commit.

---

## Task 2: Implement the `tmux-hook-run` wrapper

**Files:**
- Create: `roles/common/files/bin/tmux-hook-run`

The wrapper does four things in order: (1) run the wrapped command capturing stderr separately, (2) on failure, append a record to `~/.local/state/tmux/hooks.log`, (3) on failure, set the tmux user option `@hook-last-error` to a short truncated message, (4) always exit 0.

- [ ] **Step 1: Write the wrapper**

```bash
cat > roles/common/files/bin/tmux-hook-run <<'EOF'
#!/usr/bin/env bash
# Hook wrapper: runs a command, swallows failure (always exits 0), logs failures
# to ~/.local/state/tmux/hooks.log, and sets the tmux user option
# @hook-last-error so the status bar can surface the most recent failure.
set -u

if [ $# -lt 1 ]; then
  exit 0
fi

log_file="${HOME}/.local/state/tmux/hooks.log"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

# Run the wrapped command: discard stdout, capture stderr.
err="$("$@" 2>&1 1>/dev/null)" || rc=$?
rc="${rc:-0}"

if [ "$rc" -eq 0 ]; then
  exit 0
fi

ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
printf '[%s] exit=%d cmd=%s\nstderr: %s\n' "$ts" "$rc" "$*" "$err" >> "$log_file"

base="${1##*/}"
first_line="${err%%$'\n'*}"
if [ -n "$first_line" ]; then
  msg="${base}: ${first_line}"
else
  msg="${base}: exit ${rc}"
fi
if [ "${#msg}" -gt 60 ]; then
  msg="${msg:0:57}..."
fi

tmux set-option -gq @hook-last-error "$msg" 2>/dev/null || true

exit 0
EOF
chmod +x roles/common/files/bin/tmux-hook-run
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `bash roles/common/files/bin/tmux-hook-run.test`
Expected: `ALL TESTS PASSED` and exit 0.

- [ ] **Step 3: Commit**

```bash
git add roles/common/files/bin/tmux-hook-run
git commit
```

Commit subject: `Implement tmux-hook-run wrapper for hook-failure status indicator`.

---

## Task 3: Install `tmux-hook-run` via Ansible

**Files:**
- Modify: `roles/common/tasks/main.yml` (add `tmux-hook-run` to the existing helper-install loop)

The "Install tmux label helpers" task at roles/common/tasks/main.yml:244-256 already loops over a list of script names and copies each one. Add `tmux-hook-run` to that loop so it ships alongside the other tmux helpers.

- [ ] **Step 1: Read the current loop**

Run: `awk '/Install tmux label helpers/,/^- name:/' roles/common/tasks/main.yml | head -25`
Confirm the loop is the one with entries `tmux-devpod-name`, `tmux-label-format`, `tmux-pane-label`, `tmux-window-label`, `tmux-sync-status-visibility`, `tmux-sync-pane-border-status`.

- [ ] **Step 2: Add `tmux-hook-run` to the loop**

Edit `roles/common/tasks/main.yml` and add `    - tmux-hook-run` as a new entry after `    - tmux-sync-pane-border-status` in that loop. The block becomes:

```yaml
- name: Install tmux label helpers
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/{{ item }}'
    src: '{{ playbook_dir }}/roles/common/files/bin/{{ item }}'
    mode: 0755
  loop:
    - tmux-devpod-name
    - tmux-label-format
    - tmux-pane-label
    - tmux-window-label
    - tmux-sync-status-visibility
    - tmux-sync-pane-border-status
    - tmux-hook-run
```

- [ ] **Step 3: Run a syntax check**

Run: `cd /Users/brianjohn/projects/new-machine-bootstrap/.worktrees/tmux-patched-formula-and-indicator && ansible-playbook playbook.yml --syntax-check`
Expected: `playbook: playbook.yml` (no error).

- [ ] **Step 4: Commit**

```bash
git add roles/common/tasks/main.yml
git commit
```

Commit subject: `Install tmux-hook-run alongside other tmux helpers`.

---

## Task 4: Switch tmux.conf hooks to use the wrapper (macOS)

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf:18-26` (the three hook lines)

Replace each `run-shell -b "$HOME/.local/bin/<script> ... >/dev/null 2>>$HOME/.local/state/tmux/hooks.log || true"` with `run-shell -b "$HOME/.local/bin/tmux-hook-run <script> ..."`. The wrapper guarantees exit 0 and silences stderr internally, so `>/dev/null 2>>...` and `|| true` are no longer needed. Leave the `client-attached` hook (line 17) alone — it uses a different script and isn't part of the noise problem.

- [ ] **Step 1: Replace the three hook lines**

Edit `roles/macos/templates/dotfiles/tmux.conf`. Replace lines 18–26 (the comment block plus the three `set-hook` lines) with:

```
# Keep remote-title and window labels in sync without renaming sessions.
# tmux-hook-run logs each failure to ~/.local/state/tmux/hooks.log and updates
# @hook-last-error so the status bar surfaces the most recent failure. The
# wrapper always exits 0 — tmux never sees a failed hook.
set-hook -g pane-focus-in 'run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-remote-title publish"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-window-label #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-status-visibility #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
set-hook -g client-session-changed 'run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-remote-title publish"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-window-label #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-status-visibility #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
set-hook -g pane-title-changed 'run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-remote-title #{pane_id}"; run-shell -b "$HOME/.local/bin/tmux-hook-run tmux-sync-pane-border-status #{pane_id}"'
```

(Note that we drop the `2>>$HOME/.local/state/tmux/hooks.log || true` suffix on every line. The wrapper handles redirection and exit code internally.)

The wrapper script names (`tmux-remote-title publish`, etc.) remain identical to what the inline form invoked.

- [ ] **Step 2: Verify the file parses cleanly with no shell metacharacter ambiguity**

Run: `awk '/set-hook -g pane-focus-in/,/set-hook -g pane-title-changed/' roles/macos/templates/dotfiles/tmux.conf`
Expected: three `set-hook` lines printed verbatim, no stray quotes or stray `2>>` redirects.

- [ ] **Step 3: Commit**

```bash
git add roles/macos/templates/dotfiles/tmux.conf
git commit
```

Commit subject: `Route macOS tmux hooks through tmux-hook-run wrapper`.

---

## Task 5: Mirror the hook changes in the Linux tmux.conf

**Files:**
- Modify: `roles/linux/files/dotfiles/tmux.conf:19-26` (same three hooks)

Identical edit to Task 4, but in the Linux tmux.conf. The Linux platform also uses these hooks and the wrapper is in the common role, so the wrapper is available on both platforms.

- [ ] **Step 1: Replace the three hook lines**

Edit `roles/linux/files/dotfiles/tmux.conf`. Replace lines 19–26 (the comment block plus the three `set-hook` lines) with the same three updated `set-hook` lines from Task 4 Step 1.

- [ ] **Step 2: Verify**

Run: `awk '/set-hook -g pane-focus-in/,/set-hook -g pane-title-changed/' roles/linux/files/dotfiles/tmux.conf`
Expected: three `set-hook` lines printed verbatim.

- [ ] **Step 3: Commit**

```bash
git add roles/linux/files/dotfiles/tmux.conf
git commit
```

Commit subject: `Route Linux tmux hooks through tmux-hook-run wrapper`.

---

## Task 6: Add the status-right indicator and `prefix + H` keybind to both tmux.conf files

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf:78-81` (status-right + length)
- Modify: `roles/linux/files/dotfiles/tmux.conf:73-76` (status-right + length)
- Both files: append a `bind H` line at a sensible spot (after the existing key-binding block).

The status segment uses tmux's `#{?cond,then,else}` conditional. Inside `#[...]` style specs, commas must be escaped as `#,` so the outer conditional doesn't split on them. The keybind chains a `display-popup` and a `set-option` via `\;`.

- [ ] **Step 1: Update macOS status-right and length**

Edit `roles/macos/templates/dotfiles/tmux.conf`. Replace lines 79–81 (the `status-right ''` and `status-right-length 0` lines plus the surrounding empty status-left lines stay as-is) with:

```
set -g status-left ''
set -g status-right '#{?@hook-last-error, #[bg=colour196#,fg=white#,bold] ! #{@hook-last-error} #[default],}'
set -g status-left-length 0
set -g status-right-length 80
```

That preserves status-left empty and gives status-right enough room for a 60-char message + the surrounding ` ! ` decorations.

- [ ] **Step 2: Add the keybind to macOS conf**

Append the following near the bottom of the existing key-binding section (after the `bind-key -n M-8 display-popup ...` line, around the section that ends near line 60–65 of `roles/macos/templates/dotfiles/tmux.conf`). Pick the empty line right after that block:

```
# Hook-failure indicator: prefix + H opens the log and clears the badge.
bind H display-popup -E -h 80% -w 80% "less +G ~/.local/state/tmux/hooks.log" \; set-option -gq @hook-last-error ""
```

- [ ] **Step 3: Apply the same status-right + keybind in `roles/linux/files/dotfiles/tmux.conf`**

Same two edits — update the `status-right` / `status-right-length` lines (around lines 74–76), then append the same `# Hook-failure indicator:` comment + `bind H ...` line at the same logical location in the Linux conf.

- [ ] **Step 4: Reload check (live)**

Run: `tmux source-file roles/macos/templates/dotfiles/tmux.conf` is **not** safe (the file uses Jinja2 templating like `{{ brew_prefix }}`). Instead, run a syntax-only check by piping a stripped copy into `tmux -f /dev/stdin -L test-status-format new-session -d 'true' \; kill-server` — but the simplest correctness check is to wait until end-to-end provisioning in Task 9. Skip a manual reload here.

- [ ] **Step 5: Commit**

```bash
git add roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git commit
```

Commit subject: `Add hook-failure indicator and prefix+H to tmux status-right`.

---

## Task 7: Update `tmux-window-bar-config.test` for the new patterns

**Files:**
- Modify: `roles/common/files/bin/tmux-window-bar-config.test:48-54` (existing assertions block) and `:71-72` (the assert_tmux_file calls — those stay)

The existing test currently asserts the inline-redirect form `>/dev/null 2>>$HOME/.local/state/tmux/hooks.log || true` from PR #120. That form is gone in this change. New assertions: wrapper invocation, status-right indicator, keybind, and forbid the old inline-redirect form.

- [ ] **Step 1: Read the existing assert_tmux_file body**

Run: `awk '/^assert_tmux_file\(\)/,/^}/' roles/common/files/bin/tmux-window-bar-config.test`
This shows the helper's exact assertions. Note current lines 50–54 reference `tmux-sync-pane-border-status #{pane_id}` and the inline-redirect form.

- [ ] **Step 2: Replace the relevant lines inside `assert_tmux_file`**

Edit `roles/common/files/bin/tmux-window-bar-config.test`. Replace lines 50–55 (the four redirect-related asserts plus `tmux-session-name`) with:

```bash
  assert_contains "$file" 'tmux-hook-run tmux-sync-pane-border-status #{pane_id}'
  assert_contains "$file" 'tmux-hook-run tmux-sync-remote-title #{pane_id}'
  assert_contains "$file" 'tmux-hook-run tmux-window-label #{pane_id}'
  assert_contains "$file" 'tmux-hook-run tmux-sync-status-visibility #{pane_id}'
  assert_contains "$file" 'tmux-hook-run tmux-remote-title publish'
  assert_not_contains "$file" 'tmux-session-name'
  assert_not_contains "$file" '2>>$HOME/.local/state/tmux/hooks.log'
  assert_not_contains "$file" '>/dev/null 2>&1 || true'
  assert_contains "$file" 'set -g status-right'
  assert_contains "$file" '@hook-last-error'
  assert_contains "$file" 'set -g status-right-length 80'
  assert_contains "$file" 'bind H display-popup -E -h 80% -w 80% "less +G ~/.local/state/tmux/hooks.log"'
  assert_contains "$file" 'set-option -gq @hook-last-error ""'
```

The remaining asserts in the helper (`tmux-remote-title publish`, `window_activity_flag`, `#{window_index}`, etc.) stay unchanged.

- [ ] **Step 3: Run the test**

Run: `bash roles/common/files/bin/tmux-window-bar-config.test`
Expected: `passed=N failed=0` (all PASS lines).

- [ ] **Step 4: Commit**

```bash
git add roles/common/files/bin/tmux-window-bar-config.test
git commit
```

Commit subject: `Assert tmux-hook-run wrapper, status-right indicator, and prefix+H bind`.

---

## Task 8: Add the patched Homebrew formula

**Files:**
- Create: `roles/macos/files/homebrew/tmux-patched.rb`

The formula tracks tmux 3.6a from upstream's release tarball and applies commit `2a5715f` as a patch. SHA256 values must be computed from the actual artifacts at implementation time (not pasted from this plan, which has no way to know them).

- [ ] **Step 1: Create the homebrew directory**

Run: `mkdir -p roles/macos/files/homebrew`

- [ ] **Step 2: Compute the tarball SHA256**

Run:
```bash
curl -fsSL -o /tmp/tmux-3.6a.tar.gz https://github.com/tmux/tmux/releases/download/3.6a/tmux-3.6a.tar.gz
shasum -a 256 /tmp/tmux-3.6a.tar.gz
```
Record the 64-hex-char value as `TARBALL_SHA`.

- [ ] **Step 3: Compute the patch SHA256**

Run:
```bash
curl -fsSL -o /tmp/2a5715f.patch https://github.com/tmux/tmux/commit/2a5715fad5a3f7c7cec5ba8a0a26b85a0df2c259.patch
shasum -a 256 /tmp/2a5715f.patch
```
Record the 64-hex-char value as `PATCH_SHA`.

- [ ] **Step 4: Write the formula**

Create `roles/macos/files/homebrew/tmux-patched.rb` with the following content, substituting `<TARBALL_SHA>` and `<PATCH_SHA>` with the values from Steps 2 and 3:

```ruby
# Patched tmux 3.6a — vanilla 3.6a release plus upstream commit 2a5715f
# (https://github.com/tmux/tmux/commit/2a5715f), which fixes a NULL pointer
# dereference in window_copy_pipe_run that crashes tmux during
# copy-pipe-and-cancel when job_run returns NULL.
#
# Rollback: when upstream Homebrew tmux ships a release containing the fix,
# `bin/provision` will fail on the upstream-version-guard task. At that
# point: `brew uninstall --formula tmux-patched`; remove this formula file;
# remove the corresponding install + version-guard tasks; `brew install tmux`.

class TmuxPatched < Formula
  desc "Terminal multiplexer (3.6a + window_copy_pipe_run NULL-deref fix)"
  homepage "https://tmux.github.io/"
  url "https://github.com/tmux/tmux/releases/download/3.6a/tmux-3.6a.tar.gz"
  sha256 "<TARBALL_SHA>"
  license "ISC"

  depends_on "libevent"
  depends_on "ncurses"
  depends_on "utf8proc"

  conflicts_with "tmux", because: "Both install bin/tmux"

  patch do
    url "https://github.com/tmux/tmux/commit/2a5715fad5a3f7c7cec5ba8a0a26b85a0df2c259.patch"
    sha256 "<PATCH_SHA>"
  end

  def install
    system "./configure", *std_configure_args,
           "--sysconfdir=#{etc}",
           "--enable-utf8proc"
    system "make", "install"
  end

  test do
    assert_match "tmux 3.6a", shell_output("#{bin}/tmux -V")
  end
end
```

- [ ] **Step 5: Smoke-test the formula syntax**

Run: `brew style roles/macos/files/homebrew/tmux-patched.rb` (RuboCop-based formula linter).
Expected: no offenses, exit 0. If `brew style` is unavailable, skip — the next task installs the formula and Homebrew will surface syntax errors there.

- [ ] **Step 6: Commit**

```bash
git add roles/macos/files/homebrew/tmux-patched.rb
git commit
```

Commit subject: `Add patched tmux 3.6a Homebrew formula with window_copy_pipe_run fix`.

---

## Task 9: Wire patched-tmux install + version guard into Ansible

**Files:**
- Modify: `roles/macos/tasks/install_packages.yml:21-58` (drop `'tmux',` from the homebrew package list).
- Modify: `roles/macos/tasks/main.yml` (insert a new block after the existing tmux config tasks but **before** the `Reload tmux config` notify, so the binary is in place when config reload runs). Concretely: insert immediately above the existing `- name: Configure ghostty command` task at roles/macos/tasks/main.yml:142 (or pick another stable anchor identified in Step 1).

This is the most operationally sensitive task: removing vanilla tmux while a tmux server is running can break the user's session. We mitigate by relying on Homebrew's own atomic install behaviour (`brew install` writes the new formula's `bin/tmux` first; `brew uninstall` unlinks the old formula's `bin/tmux` after, but for `conflicts_with` Homebrew refuses to install until the conflict is gone) — so the order is: detect vanilla → uninstall → install patched.

- [ ] **Step 1: Identify the Ansible insertion anchor**

Run: `grep -nE "^- name:" roles/macos/tasks/main.yml | head -20`
Pick the line for `- name: Configure ghostty command` (or whatever name comes immediately after the existing tmux config copy tasks at line ~142). Record the line number.

- [ ] **Step 2: Drop vanilla `tmux` from the homebrew package list**

Edit `roles/macos/tasks/install_packages.yml`. In the `Install Brew packages` task at line 19, remove the line `      'tmux',` from the `name:` list. The list otherwise stays unchanged.

- [ ] **Step 3: Add the patched-tmux install + version-guard block to `roles/macos/tasks/main.yml`**

Insert the following block immediately above the anchor identified in Step 1:

```yaml
- name: Detect vanilla Homebrew tmux
  ansible.builtin.command: brew list --formula --versions tmux
  register: vanilla_tmux_check
  changed_when: false
  failed_when: false

- name: Uninstall vanilla Homebrew tmux (replaced by patched formula)
  community.general.homebrew:
    name: tmux
    state: absent
  when: vanilla_tmux_check.rc == 0

- name: Detect installed patched tmux version
  ansible.builtin.command: brew list --formula --versions tmux-patched
  register: patched_tmux_check
  changed_when: false
  failed_when: false

- name: Install patched Homebrew tmux formula
  ansible.builtin.command:
    cmd: 'brew install --formula {{ playbook_dir }}/roles/macos/files/homebrew/tmux-patched.rb'
  when: '"3.6a" not in patched_tmux_check.stdout'
  notify: Reload tmux config

- name: Query upstream Homebrew tmux version
  ansible.builtin.command: brew info --json=v2 tmux
  register: upstream_tmux_info
  changed_when: false

- name: Fail if upstream Homebrew tmux has moved past 3.6a
  ansible.builtin.fail:
    msg: |
      Upstream Homebrew tmux is now {{ upstream_version }}; the patched-3.6a
      workaround in this repo can be removed.

      Steps:
        1. brew uninstall --formula tmux-patched
        2. Delete roles/macos/files/homebrew/tmux-patched.rb
        3. Remove the patched-tmux install + version-guard tasks from
           roles/macos/tasks/main.yml
        4. Re-add 'tmux' to the homebrew package list in
           roles/macos/tasks/install_packages.yml
        5. Commit and re-run bin/provision
  vars:
    upstream_version: '{{ (upstream_tmux_info.stdout | from_json).formulae[0].versions.stable }}'
  when: upstream_version != "3.6a"
```

- [ ] **Step 4: Run an Ansible syntax check**

Run: `ansible-playbook playbook.yml --syntax-check`
Expected: `playbook: playbook.yml` and exit 0.

- [ ] **Step 5: Run a check-mode dry run**

Run: `bin/provision --check --diff 2>&1 | tail -120`
Expected: shows the new tasks would run; no failures except possibly the version guard if upstream actually moved (it shouldn't have on the day of writing).

- [ ] **Step 6: Commit**

```bash
git add roles/macos/tasks/install_packages.yml roles/macos/tasks/main.yml
git commit
```

Commit subject: `Install patched tmux 3.6a and guard against upstream version drift`.

---

## Task 10: End-to-end verification

**Files:**
- None (verification only, no commit unless verification finds an issue and fixes it).

The user's machine is the target. Apply the plan live and confirm: vanilla tmux is gone, patched tmux is installed, hooks route through the wrapper, the status indicator works, and the version guard's failure path is reachable.

- [ ] **Step 1: Run a real provision**

Run: `bin/provision --diff 2>&1 | tee /tmp/tmux-patched-provision.log | tail -40`
Expected: ends with `PLAY RECAP ... failed=0`; intermediate output shows the vanilla-uninstall and patched-install tasks running (or skipping if already in place from a prior partial run).

- [ ] **Step 2: Confirm tmux binary is patched**

Run: `brew list --formula --versions tmux-patched`
Expected: `tmux-patched 3.6a`.

Run: `brew list --formula --versions tmux 2>/dev/null && echo VANILLA-STILL-PRESENT || echo VANILLA-GONE`
Expected: `VANILLA-GONE`.

Run: `which tmux && tmux -V`
Expected: a Homebrew-prefixed path; `tmux 3.6a`.

- [ ] **Step 3: Reload the running tmux server's config**

Run: `tmux source-file ~/.tmux.conf 2>&1`
Expected: exit 0 (or only a benign tpm warning that we already saw in PR #120's verification).

Run: `tmux show-hooks -wg -t @0 2>&1 | grep -E 'pane-focus-in|pane-title-changed'`
Expected: both hooks contain `tmux-hook-run` and not `2>>$HOME/.local/state/tmux/hooks.log`.

- [ ] **Step 4: Manually trigger a hook failure and confirm the indicator surfaces**

Run: `~/.local/bin/tmux-hook-run /bin/false; tmux show-options -gqv @hook-last-error`
Expected: `false: exit 1` (or similar — the shape `<basename>: exit <code>` from the wrapper's fallback path).

Inspect the live tmux status bar visually: a red ` ! false: exit 1 ` badge should appear on the right side of the status row.

- [ ] **Step 5: Dismiss with the keybind**

Press `prefix + H`. A popup should open showing the contents of `~/.local/state/tmux/hooks.log`. Press `q`. The popup closes; the red badge disappears.

Cross-check programmatically: `tmux show-options -gqv @hook-last-error` after dismissal should print an empty line.

- [ ] **Step 6: Confirm the version guard's failure path is reachable**

Run: `bin/provision --diff` after temporarily editing `roles/macos/files/homebrew/tmux-patched.rb` to claim a different version (or, more cleanly, mock the upstream JSON by swapping `brew` on PATH for the duration of one run). The simplest evidence of reachability: `ansible-playbook playbook.yml --syntax-check` from Task 9 already validated the YAML; Step 5 of Task 9 already exercised the `when` clause. If you want to actually trip the guard once, run:

```bash
ansible-playbook playbook.yml --check --extra-vars 'upstream_tmux_info={"stdout":"{\"formulae\":[{\"versions\":{\"stable\":\"3.7\"}}]}"}'
```

Expected: the `Fail if upstream Homebrew tmux has moved past 3.6a` task fails with the rollback message embedded in Task 9 Step 3.

- [ ] **Step 7: No commit unless something failed and got fixed**

If any verification step prompted a fix, commit it with a descriptive subject. Otherwise this task produces no commit and only confirms the pipeline is healthy end-to-end.

---

## Self-review summary

- Spec coverage: every section of the spec maps to one or more tasks. Patched formula → Tasks 8–9. Version guard → Task 9 (Steps 3, 6). Hook indicator → Tasks 1–7 (wrapper + tests + Ansible install + tmux.conf changes + status segment + keybind + repo-test updates).
- Placeholders: only `<TARBALL_SHA>` and `<PATCH_SHA>` exist as intentional placeholders. Steps 2–3 of Task 8 produce them on the executor's machine.
- Type/symbol consistency: `@hook-last-error` is the only tmux user option referenced; spelled the same in the wrapper, status-right format, keybind, and tests. Wrapper called `tmux-hook-run` everywhere. Log file path `~/.local/state/tmux/hooks.log` is identical across wrapper, keybind, and the existing directory-creation task added in PR #120.
