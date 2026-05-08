# tmux Pane Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A repo-local script `tmux-pane-link` other repos and skills can call to attach a clickable identifier (e.g. `GH#1234`) to the current tmux pane via OSC 8, rendered next to the existing repo label, auto-cleared on `repo-end`.

**Architecture:** New bash script writes a per-pane user option `@pane-link` containing a pre-rendered tmux style string (`#[hyperlink="URL"]LABEL#[hyperlink=]`). `pane-border-format` interpolates the option. The existing `tmux-agent-worktree clear` (called by `repo-end`) is extended to also clear `@pane-link`. The script honors `TMUX_AGENT_WORKTREE_STATE_DIR` for filesystem-backed unit testing, the same convention as `tmux-agent-worktree`.

**Tech Stack:** Bash 3.2+ (macOS default), tmux 3.4+ (3.6a installed), Ghostty (cmd+click on OSC 8), Ansible for deployment, GitHub Actions for CI.

---

## File Structure

- **Create** `roles/common/files/bin/tmux-pane-link` — the script (executable, 0755)
- **Create** `tests/tmux-pane-link.sh` — bash test harness, mirroring `tests/tmux-label-contract.sh` style
- **Modify** `roles/common/files/bin/tmux-agent-worktree:219` — add one `clear_pane_option ... @pane-link` line in `cmd_clear`
- **Modify** `roles/common/tasks/main.yml:290-300` — add `tmux-pane-link` to the "Install tmux label helpers" loop
- **Modify** `roles/macos/templates/dotfiles/tmux.conf:124` — extend `pane-border-format`
- **Modify** `roles/linux/files/dotfiles/tmux.conf:116` — same extension to the Linux copy
- **Modify** `.github/workflows/integration-test.yml` — add a step that runs `bash tests/tmux-pane-link.sh`

---

## Task 1: Test scaffold + CI wiring

**Why first:** `tests/ci-test-inventory.sh` enforces that every file under `tests/` is referenced by a workflow step. If a test file is committed without a matching workflow entry, that contract test fails. Wiring the empty harness first means each subsequent task adds cases to a file that already passes inventory.

**Files:**
- Create: `tests/tmux-pane-link.sh`
- Modify: `.github/workflows/integration-test.yml`

- [ ] **Step 1: Create the test scaffold**

Create `tests/tmux-pane-link.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
PANE_LINK="$BIN_DIR/tmux-pane-link"
AGENT_WORKTREE="$BIN_DIR/tmux-agent-worktree"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() {
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  printf 'FAIL  %s\n%s\n' "$1" "$2" >&2
  exit 1
}

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if ! grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "missing '$needle' in $path (got: $(cat "$path"))"
  fi
  pass_case "$name"
}

assert_no_file() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    fail_case "$name" "expected absent: $path"
  fi
  pass_case "$name"
}

# Test cases get added below by subsequent tasks.

printf 'tmux pane-link checks complete\n'
```

Mark executable:

```bash
chmod +x tests/tmux-pane-link.sh
```

- [ ] **Step 2: Add the workflow step**

Open `.github/workflows/integration-test.yml`. After the `Verify tmux label contract` step (the one that runs `bash tests/tmux-label-contract.sh`), add:

```yaml
      - name: Verify tmux pane-link contract
        run: bash tests/tmux-pane-link.sh
```

- [ ] **Step 3: Run ci-test-inventory.sh to verify wiring**

Run: `bash tests/ci-test-inventory.sh`
Expected: `PASS  every tracked test-like file is referenced by CI` and exit 0.

- [ ] **Step 4: Run the empty test harness**

Run: `bash tests/tmux-pane-link.sh`
Expected: `tmux pane-link checks complete` and exit 0. (No assertions yet.)

- [ ] **Step 5: Commit**

```bash
git add tests/tmux-pane-link.sh .github/workflows/integration-test.yml
git commit  # invoke the _commit skill — do not run git commit directly
```

Use the `_commit` skill (per repo policy). Commit message body: "Add empty tmux-pane-link test harness and CI wiring."

---

## Task 2: Set with valid http(s) URL writes the OSC 8-formatted option

**Files:**
- Modify: `tests/tmux-pane-link.sh` (add cases)
- Create: `roles/common/files/bin/tmux-pane-link`

- [ ] **Step 1: Add the failing test cases**

Insert before the final `printf 'tmux pane-link checks complete\n'` line:

```bash
# Case: set with valid https URL writes OSC 8 hyperlink to @pane-link
state_dir="$TMPROOT/state-https"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "GH1234" "https://example.com/pulls/1234"
assert_file_contains \
  "$state_dir/%1.@pane-link" \
  '#[hyperlink="https://example.com/pulls/1234"]GH1234#[hyperlink=]' \
  "set with https writes OSC 8 hyperlink"

# Case: set with valid http URL also works
state_dir="$TMPROOT/state-http"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" "http://example.com"
assert_file_contains \
  "$state_dir/%1.@pane-link" \
  '#[hyperlink="http://example.com"]x#[hyperlink=]' \
  "set with http writes OSC 8 hyperlink"
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/tmux-pane-link.sh`
Expected: FAIL — script `roles/common/files/bin/tmux-pane-link` does not exist yet, so `"$PANE_LINK"` invocation errors with a "No such file or directory" failure before `assert_file_contains` ever runs. The bash exit (`set -e`) terminates the script.

- [ ] **Step 3: Create the minimal script**

Create `roles/common/files/bin/tmux-pane-link`:

```bash
#!/usr/bin/env bash
# Attach a clickable link annotation (OSC 8) to the current tmux pane.
# Stored as the @pane-link user option, rendered by pane-border-format.
set -u

write_pane_option() {
  local pane="$1" name="$2" value="$3"
  if [ -n "${TMUX_AGENT_WORKTREE_STATE_DIR:-}" ]; then
    mkdir -p "$TMUX_AGENT_WORKTREE_STATE_DIR"
    printf '%s' "$value" > "$TMUX_AGENT_WORKTREE_STATE_DIR/$pane.$name"
  else
    tmux set-option -pq -t "$pane" "$name" "$value" 2>/dev/null || true
  fi
}

[ -n "${TMUX:-}" ] || exit 0

label="${1:-}"
url="${2:-}"
pane="${TMUX_PANE:-}"
[ -n "$pane" ] || exit 0

value="#[hyperlink=\"$url\"]$label#[hyperlink=]"
write_pane_option "$pane" "@pane-link" "$value"
```

Mark executable:

```bash
chmod +x roles/common/files/bin/tmux-pane-link
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/tmux-pane-link.sh`
Expected: `PASS  set with https writes OSC 8 hyperlink`, `PASS  set with http writes OSC 8 hyperlink`, then `tmux pane-link checks complete`.

- [ ] **Step 5: Commit**

Use the `_commit` skill. Message body: "Add tmux-pane-link script with happy-path set."

---

## Task 3: --clear unsets the option

**Files:**
- Modify: `tests/tmux-pane-link.sh` (add case)
- Modify: `roles/common/files/bin/tmux-pane-link`

- [ ] **Step 1: Add the failing test case**

Append before `printf 'tmux pane-link checks complete\n'`:

```bash
# Case: --clear removes the @pane-link option
state_dir="$TMPROOT/state-clear"
mkdir -p "$state_dir"
printf 'preexisting' > "$state_dir/%1.@pane-link"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" --clear
assert_no_file "$state_dir/%1.@pane-link" "--clear removes @pane-link"
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/tmux-pane-link.sh`
Expected: FAIL on `--clear removes @pane-link`. The current minimal script treats `--clear` as the LABEL and writes a file named `%1.@pane-link` containing `#[hyperlink="..."]--clear#[hyperlink=]`, so the file is still present.

- [ ] **Step 3: Implement the --clear path**

Replace the body of `roles/common/files/bin/tmux-pane-link` after the `write_pane_option` helper (everything below `[ -n "${TMUX:-}" ] || exit 0`) with:

```bash
clear_pane_option() {
  local pane="$1" name="$2"
  if [ -n "${TMUX_AGENT_WORKTREE_STATE_DIR:-}" ]; then
    rm -f "$TMUX_AGENT_WORKTREE_STATE_DIR/$pane.$name"
  else
    tmux set-option -pqu -t "$pane" "$name" 2>/dev/null || true
  fi
}

[ -n "${TMUX:-}" ] || exit 0

clear_mode=0
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --clear) clear_mode=1; shift ;;
    *)       positional+=("$1"); shift ;;
  esac
done

pane="${TMUX_PANE:-}"
[ -n "$pane" ] || exit 0

if [ "$clear_mode" -eq 1 ]; then
  clear_pane_option "$pane" "@pane-link"
  exit 0
fi

label="${positional[0]:-}"
url="${positional[1]:-}"
value="#[hyperlink=\"$url\"]$label#[hyperlink=]"
write_pane_option "$pane" "@pane-link" "$value"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/tmux-pane-link.sh`
Expected: all three previous cases pass plus `PASS  --clear removes @pane-link`.

- [ ] **Step 5: Commit**

Use `_commit`. Message body: "Add --clear to tmux-pane-link."

---

## Task 4: URL validation (scheme, control chars, quote, backslash)

**Files:**
- Modify: `tests/tmux-pane-link.sh`
- Modify: `roles/common/files/bin/tmux-pane-link`

- [ ] **Step 1: Add the failing test cases**

Append before the trailing `printf`:

```bash
# Case: javascript: scheme rejected
state_dir="$TMPROOT/state-bad-js"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" "javascript:alert(1)"
rc=$?
set -e
assert_equals "$rc" "2" "javascript: URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "javascript: URL writes nothing"

# Case: file:// scheme rejected
state_dir="$TMPROOT/state-bad-file"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" "file:///etc/passwd"
rc=$?
set -e
assert_equals "$rc" "2" "file:// URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "file:// URL writes nothing"

# Case: scheme-less URL rejected
state_dir="$TMPROOT/state-bad-bare"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" "example.com"
rc=$?
set -e
assert_equals "$rc" "2" "scheme-less URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "scheme-less URL writes nothing"

# Case: control character in URL rejected
state_dir="$TMPROOT/state-bad-ctrl"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" $'https://example.com/\x1b]8;;evil\x1b\\'
rc=$?
set -e
assert_equals "$rc" "2" "URL with ESC byte exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with ESC byte writes nothing"

# Case: backslash in URL rejected
state_dir="$TMPROOT/state-bad-bs"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" 'https://example.com/\bad'
rc=$?
set -e
assert_equals "$rc" "2" "URL with backslash exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with backslash writes nothing"

# Case: double-quote in URL rejected
state_dir="$TMPROOT/state-bad-dq"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" 'https://example.com/"injected'
rc=$?
set -e
assert_equals "$rc" "2" "URL with double-quote exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with double-quote writes nothing"
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `bash tests/tmux-pane-link.sh`
Expected: FAIL on the first new case — the current script exits 0 and writes the option for any URL.

- [ ] **Step 3: Add validation to the script**

Insert immediately before the existing `value="#[hyperlink=...]"` line:

```bash
err() {
  printf 'tmux-pane-link: %s\n' "$1" >&2
  exit 2
}

# URL must start with http:// or https://
case "$url" in
  http://*|https://*|HTTP://*|HTTPS://*) ;;
  *) err "URL must start with http:// or https://" ;;
esac

# URL must not contain control characters, backslash, or double-quote.
if printf '%s' "$url" | LC_ALL=C grep -qE '[[:cntrl:]"\\]'; then
  err "URL contains forbidden character"
fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/tmux-pane-link.sh`
Expected: all cases pass.

- [ ] **Step 5: Commit**

Use `_commit`. Message body: "Validate URL scheme and forbidden characters in tmux-pane-link."

---

## Task 5: LABEL `#` escaping

**Files:**
- Modify: `tests/tmux-pane-link.sh`
- Modify: `roles/common/files/bin/tmux-pane-link`

`#` is tmux's format-string meta-character. If a LABEL like `GH#1234` is interpolated raw into pane-border-format via `#{@pane-link}`, tmux re-parses the value and reads `#1` as the start of a (probably broken) format directive. Doubling each `#` to `##` is the standard tmux escape.

- [ ] **Step 1: Add the failing test case**

Append:

```bash
# Case: # in LABEL is doubled to ## so tmux's format parser treats it as literal
state_dir="$TMPROOT/state-hash"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "GH#1234" "https://example.com"
assert_file_contains \
  "$state_dir/%1.@pane-link" \
  '#[hyperlink="https://example.com"]GH##1234#[hyperlink=]' \
  "# in LABEL is doubled in stored value"
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/tmux-pane-link.sh`
Expected: FAIL — current script writes the literal `GH#1234` LABEL without escaping.

- [ ] **Step 3: Implement escaping**

Insert immediately before `value="#[hyperlink=\"$url\"]$label#[hyperlink=]"`:

```bash
label="${label//#/##}"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/tmux-pane-link.sh`
Expected: all cases pass.

- [ ] **Step 5: Commit**

Use `_commit`. Message body: "Escape # in tmux-pane-link LABEL."

---

## Task 6: LABEL truncation at 64 characters

**Files:**
- Modify: `tests/tmux-pane-link.sh`
- Modify: `roles/common/files/bin/tmux-pane-link`

- [ ] **Step 1: Add the failing test case**

Append:

```bash
# Case: LABEL longer than 64 chars is truncated to 63 chars + …
state_dir="$TMPROOT/state-trunc"
long="$(printf 'a%.0s' {1..100})"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "$long" "https://example.com"
content="$(cat "$state_dir/%1.@pane-link")"
expected_label="$(printf 'a%.0s' {1..63})…"
assert_file_contains \
  "$state_dir/%1.@pane-link" \
  "]${expected_label}#[" \
  "long LABEL truncated to 63 chars + ellipsis"
# Confirm the un-truncated 100-char run did NOT survive.
if grep -Fq "$(printf 'a%.0s' {1..100})" "$state_dir/%1.@pane-link"; then
  fail_case "long LABEL truncated to 63 chars + ellipsis" \
    "found 100-char run in: $content"
fi
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/tmux-pane-link.sh`
Expected: FAIL — current script does not truncate.

- [ ] **Step 3: Implement truncation**

Insert immediately before the `label="${label//#/##}"` escaping line:

```bash
if [ "${#label}" -gt 64 ]; then
  label="${label:0:63}…"
fi
```

(Truncation runs before `#`-escaping so the budget is on the visible label.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/tmux-pane-link.sh`
Expected: all cases pass.

- [ ] **Step 5: Commit**

Use `_commit`. Message body: "Truncate long LABEL in tmux-pane-link to 64 chars."

---

## Task 7: No-`$TMUX` exits silently (and writes nothing)

The script must be safe for callers in arbitrary environments. A skill in another repo invoking `tmux-pane-link` outside a tmux session must not error — the spec says exit 0, write nothing.

**Files:**
- Modify: `tests/tmux-pane-link.sh`

The script already has `[ -n "${TMUX:-}" ] || exit 0` from Task 2. This task locks in the behavior with a regression test.

- [ ] **Step 1: Add the regression test**

Append:

```bash
# Case: no $TMUX → exit 0, no write, even with otherwise-valid args
state_dir="$TMPROOT/state-no-tmux"
mkdir -p "$state_dir"
( unset TMUX; \
  TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
    "$PANE_LINK" "GH1" "https://example.com" )
assert_no_file "$state_dir/%1.@pane-link" "no \$TMUX writes nothing"
```

- [ ] **Step 2: Run the tests**

Run: `bash tests/tmux-pane-link.sh`
Expected: PASS on the new case (the existing guard already handles it). All previous cases still pass.

- [ ] **Step 3: Commit**

Use `_commit`. Message body: "Lock in no-TMUX silent exit for tmux-pane-link."

---

## Task 8: `--pane PANE_ID` flag for explicit targeting

Lets callers target a pane other than `$TMUX_PANE` (useful for hooks running detached).

**Files:**
- Modify: `tests/tmux-pane-link.sh`
- Modify: `roles/common/files/bin/tmux-pane-link`

- [ ] **Step 1: Add the failing test cases**

Append:

```bash
# Case: --pane targets the specified pane id (without $TMUX_PANE)
state_dir="$TMPROOT/state-pane-flag"
( unset TMUX_PANE; \
  TMUX=1 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
    "$PANE_LINK" --pane "%9" "x" "https://example.com" )
assert_file_contains \
  "$state_dir/%9.@pane-link" \
  '#[hyperlink="https://example.com"]x#[hyperlink=]' \
  "--pane targets the specified pane id"

# Case: --pane combines with --clear
state_dir="$TMPROOT/state-pane-clear"
mkdir -p "$state_dir"
printf 'present' > "$state_dir/%9.@pane-link"
TMUX=1 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" --pane "%9" --clear
assert_no_file "$state_dir/%9.@pane-link" "--pane --clear removes from named pane"
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `bash tests/tmux-pane-link.sh`
Expected: FAIL on the first new case — the script does not recognize `--pane` and treats it as a positional arg.

- [ ] **Step 3: Implement the flag**

In the option-parsing `while` loop, replace:

```bash
while [ $# -gt 0 ]; do
  case "$1" in
    --clear) clear_mode=1; shift ;;
    *)       positional+=("$1"); shift ;;
  esac
done

pane="${TMUX_PANE:-}"
```

with:

```bash
pane=""
while [ $# -gt 0 ]; do
  case "$1" in
    --clear) clear_mode=1; shift ;;
    --pane)  pane="${2:-}"; shift 2 ;;
    *)       positional+=("$1"); shift ;;
  esac
done

[ -n "$pane" ] || pane="${TMUX_PANE:-}"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/tmux-pane-link.sh`
Expected: all cases pass.

- [ ] **Step 5: Commit**

Use `_commit`. Message body: "Add --pane flag to tmux-pane-link for explicit targeting."

---

## Task 9: Refresh client after set/clear

Pane border re-renders on `status-interval` (60s in this repo). To make the annotation appear immediately after the script returns, fire `tmux refresh-client -S`. Skip the call when the state-dir override is active (tests).

**Files:**
- Modify: `roles/common/files/bin/tmux-pane-link`

This task has no automated test (no straightforward way to assert without spinning up a fake tmux). The change is small and the spec called it out explicitly.

- [ ] **Step 1: Add the refresh helper**

Below the `clear_pane_option` function in the script, add:

```bash
refresh_client() {
  [ -n "${TMUX_AGENT_WORKTREE_STATE_DIR:-}" ] && return 0
  tmux refresh-client -S 2>/dev/null || true
}
```

- [ ] **Step 2: Call it after set and clear**

In the `if [ "$clear_mode" -eq 1 ]` block, after `clear_pane_option`, add:

```bash
  refresh_client
```

After the final `write_pane_option` call (end of the script), add:

```bash
refresh_client
```

- [ ] **Step 3: Run the existing tests to confirm no regression**

Run: `bash tests/tmux-pane-link.sh`
Expected: all cases pass. The state-dir override path skips the refresh, so tests are unaffected.

- [ ] **Step 4: Commit**

Use `_commit`. Message body: "Refresh tmux client immediately after pane-link change."

---

## Task 10: `tmux-agent-worktree clear` also clears `@pane-link`

**Files:**
- Modify: `tests/tmux-pane-link.sh`
- Modify: `roles/common/files/bin/tmux-agent-worktree:219`

- [ ] **Step 1: Add the failing test case**

Append to `tests/tmux-pane-link.sh`:

```bash
# Case: tmux-agent-worktree clear (the path repo-end calls) also removes @pane-link.
state_dir="$TMPROOT/state-aw-clear"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "GH1" "https://example.com"
[ -f "$state_dir/%1.@pane-link" ] || \
  fail_case "tmux-agent-worktree clear removes @pane-link" "set did not write the option"

# tmux-agent-worktree's cmd_clear shells out to tmux-window-label and
# tmux-remote-title; stub them so the test does not need a real tmux server.
stub_bin="$TMPROOT/aw-clear-stub-bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat >"$stub_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$stub_bin/tmux-window-label" "$stub_bin/tmux-remote-title"

TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
PATH="$stub_bin:$PATH" \
  "$AGENT_WORKTREE" clear
assert_no_file "$state_dir/%1.@pane-link" \
  "tmux-agent-worktree clear removes @pane-link"
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash tests/tmux-pane-link.sh`
Expected: FAIL on `tmux-agent-worktree clear removes @pane-link`. The current `cmd_clear` does not touch `@pane-link`.

- [ ] **Step 3: Add the clear line**

Edit `roles/common/files/bin/tmux-agent-worktree`. Find `cmd_clear` (currently around line 214–222):

```bash
cmd_clear() {
  [ -n "${TMUX:-}" ] || return 0
  [ -n "${TMUX_PANE:-}" ] || return 0
  clear_pane_option "$TMUX_PANE" "@agent_worktree_path"
  clear_pane_option "$TMUX_PANE" "@agent_worktree_pid"
  clear_pane_option "$TMUX_PANE" "@pane-label"
  refresh_window_label
  publish_title
}
```

Add one line after the `@pane-label` clear:

```bash
  clear_pane_option "$TMUX_PANE" "@pane-link"
```

The full block becomes:

```bash
cmd_clear() {
  [ -n "${TMUX:-}" ] || return 0
  [ -n "${TMUX_PANE:-}" ] || return 0
  clear_pane_option "$TMUX_PANE" "@agent_worktree_path"
  clear_pane_option "$TMUX_PANE" "@agent_worktree_pid"
  clear_pane_option "$TMUX_PANE" "@pane-label"
  clear_pane_option "$TMUX_PANE" "@pane-link"
  refresh_window_label
  publish_title
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/tmux-pane-link.sh`
Expected: all cases pass, including the new one.

Also run the existing label contract test to confirm no regression:

Run: `bash tests/tmux-label-contract.sh`
Expected: all PASS lines, exit 0.

- [ ] **Step 5: Commit**

Use `_commit`. Message body: "Clear @pane-link on tmux-agent-worktree clear."

---

## Task 11: Render `@pane-link` in `pane-border-format` (macOS + Linux)

Two near-identical edits to two tmux config files. The rendered annotation appears between the existing label and the error indicator, with a leading space that is only present when a link is set.

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf:124`
- Modify: `roles/linux/files/dotfiles/tmux.conf:116`

This task has no automated test (asserting tmux's rendered output requires a live tmux session). The manual e2e in Task 12 covers it.

- [ ] **Step 1: Edit the macOS tmux.conf**

In `roles/macos/templates/dotfiles/tmux.conf`, the line at 124 reads:

```
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #{?#{@pane-label},#{@pane-label},#{b:pane_current_path} | #{host_short}}#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #[default],} '
```

Replace it with:

```
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #{?#{@pane-label},#{@pane-label},#{b:pane_current_path} | #{host_short}}#{?#{@pane-link}, #{@pane-link},}#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #[default],} '
```

The diff is a single insertion of `#{?#{@pane-link}, #{@pane-link},}` between the label segment and the error segment.

- [ ] **Step 2: Edit the Linux tmux.conf**

In `roles/linux/files/dotfiles/tmux.conf`, the line at 116 has identical text. Make the identical insertion.

- [ ] **Step 3: Sanity-check the diff**

Run: `git diff roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf`
Expected: each file shows one removed line and one added line, differing only by the inserted `#{?#{@pane-link}, #{@pane-link},}` segment.

- [ ] **Step 4: Commit**

Use `_commit`. Message body: "Render @pane-link in tmux pane-border-format on macOS and Linux."

---

## Task 12: Ansible deployment + provision + manual e2e

**Files:**
- Modify: `roles/common/tasks/main.yml:290-300`

- [ ] **Step 1: Add `tmux-pane-link` to the install loop**

In `roles/common/tasks/main.yml`, find the task:

```yaml
- name: Install tmux label helpers
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/{{ item }}'
    src: '{{ playbook_dir }}/roles/common/files/bin/{{ item }}'
    mode: 0755
  loop:
    - tmux-devpod-name
    - tmux-pane-label
    - tmux-update-pane-label
    - tmux-update-all-pane-labels
    - tmux-window-label
    - tmux-sync-status-visibility
    - tmux-sync-pane-border-status
    - tmux-pane-title-changed
    - tmux-hook-run
    - report-pane-error
```

Add `- tmux-pane-link` to the `loop:` (anywhere; alphabetical placement after `tmux-pane-label` is consistent with siblings).

- [ ] **Step 2: Run provisioning**

Run: `bin/provision`
Expected: completes without errors. The new file appears at `~/.local/bin/tmux-pane-link` (mode 0755). Updated `~/.tmux.conf` reflects the new `pane-border-format`.

- [ ] **Step 3: Reload tmux config**

Run: `tmux source-file ~/.tmux.conf`
Expected: no error.

- [ ] **Step 4: Manual e2e — set, click, clear**

Inside Ghostty + tmux, in any pane:

```bash
tmux-pane-link "GH#1" "https://example.com"
```

Expected: the pane border bottom shows the existing label followed by ` GH#1 ` (the `#1` rendered correctly, not eaten by the format parser).

Hold cmd, click on `GH#1`. Expected: browser opens to `https://example.com`.

```bash
tmux-pane-link --clear
```

Expected: ` GH#1 ` disappears from the border within a refresh.

- [ ] **Step 5: Manual e2e — `tmux-agent-worktree clear` clears the link**

`repo-end` deletes the worktree, which is disruptive for an in-place test. Exercise the integration point directly:

```bash
tmux-pane-link "GH#42" "https://example.com"
# verify the annotation is visible
tmux-agent-worktree clear
# verify the GH#42 annotation (and the repo-aware label) disappear
```

Expected: both annotations gone after the clear. `repo-end` calls the same `tmux-agent-worktree clear` path under the hood, so this verifies the production lifecycle.

- [ ] **Step 6: Run the full test inventory once locally**

Run: `bash tests/ci-test-inventory.sh && bash tests/tmux-pane-link.sh && bash tests/tmux-label-contract.sh`
Expected: all PASS lines, exit 0 for each.

- [ ] **Step 7: Commit**

Use `_commit`. Message body: "Deploy tmux-pane-link via Ansible."

---

## Verification checklist (before opening PR)

- [ ] `bash tests/ci-test-inventory.sh` passes (every test wired to CI).
- [ ] `bash tests/tmux-pane-link.sh` passes (10+ cases).
- [ ] `bash tests/tmux-label-contract.sh` passes (no regression in sibling test).
- [ ] `bin/provision` succeeds.
- [ ] Manual e2e in Ghostty: link visible, cmd+click opens browser, `--clear` removes it.
- [ ] `repo-end` removes the annotation.
- [ ] No edits to deployed files in `~`; all changes are in this repo.
