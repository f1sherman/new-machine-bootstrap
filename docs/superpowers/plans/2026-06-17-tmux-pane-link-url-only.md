# URL-only PR pane link, rendered first — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the bare PR URL (no `gh#`/`fj#` reference) first in the tmux pane border so the clickable link never gets pushed off a narrow pane.

**Architecture:** Three managed files change. `tmux-pane-link` stores only the URL in `@pane-link`. `tmux-agent-worktree` emits and forwards only the URL. Both `tmux.conf` files reorder `pane-border-format` so `@pane-link` renders before the branch/repo label. Tests live in the existing `tests/tmux-label-contract.sh` (already wired into CI).

**Tech Stack:** Bash, jq, tmux format strings, Ansible-managed dotfiles. No new dependencies.

## Global Constraints

- This repository is **public**: no employer names, internal repo names, ticket prefixes, employee handles, or internal tooling references (incl. devpods/codespaces) in code, comments, commits, or docs.
- Never edit deployed files in `~`; all changes go in this repo and apply via `bin/provision`.
- Comments sparingly; explain why, not what. No ticket/issue refs.
- The `tmux-pane-link` interface and the `tmux-agent-worktree` call site are coupled — they must change together (Task 1) or the `%10` contract test breaks.
- Do not add new test files: extend `tests/tmux-label-contract.sh`, which is already registered in `.github/workflows/integration-test.yml` and validated by `tests/ci-test-inventory.sh`.

---

### Task 1: Store and forward the PR URL only (drop the `gh#`/`fj#` reference)

**Files:**
- Modify: `roles/common/files/bin/tmux-pane-link` (lines 1–5 comment, 60–61, 79–86)
- Modify: `roles/common/files/bin/tmux-agent-worktree` (jq block ~263–268, `publish_cached_pr_pane_link_for_path` ~275–299)
- Test: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: PR-status cache JSON written by upstream (`display_ref`, `html_url`, `state`, `expires_at_epoch`, `remote_url`, `branch`).
- Produces:
  - `tmux-pane-link [--pane P] [--clear] <url>` — `<url>` is the single positional; stored verbatim (after `#`→`##` escaping) in the `@pane-link` pane option. No label argument.
  - `cached_pr_pane_link_for_path <path>` now prints just the PR URL (one line) on success, nothing on failure.

- [ ] **Step 1: Write the failing tests**

In `tests/tmux-label-contract.sh`, add a direct `tmux-pane-link` unit test. Put it just after the `BIN_DIR`/`AGENT_WORKTREE` variable block near the top (add the `PANE_LINK` var there), and place the invocation+assert after the existing `create_repo`/`write_pr_status_cache` helper definitions, before the first existing assertion:

```bash
PANE_LINK="$BIN_DIR/tmux-pane-link"
```

```bash
pane_link_state_dir="$TMPROOT/state-pane-link"
mkdir -p "$pane_link_state_dir"
direct_url="https://github.com/org/repo/pull/7"
TMUX=1 \
TMUX_AGENT_WORKTREE_STATE_DIR="$pane_link_state_dir" \
  "$PANE_LINK" --pane %20 "$direct_url"
assert_equals "$(cat "$pane_link_state_dir/%20.@pane-link")" "$direct_url" "tmux-pane-link stores bare URL with no label"
```

Then change the existing `%10` cached-PR assertion. Replace this line:

```bash
assert_file_contains "$cache_state_dir/%10.@pane-link" "fj##42 $pr_url" "repo-start tmux writer publishes cached PR URL"
```

with an exact-match assertion (the old substring check would still pass against the old `fj##42 <url>` value, so it must become exact):

```bash
assert_equals "$(cat "$cache_state_dir/%10.@pane-link")" "$pr_url" "repo-start tmux writer publishes bare cached PR URL"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/tmux-label-contract.sh`
Expected: FAIL. The direct test fails because the current `tmux-pane-link` treats the URL as the `label` positional and finds an empty `url` (URL validation error, no file written). The `%10` assertion fails because the current code stores `fj##42 <url>`, not the bare URL.

- [ ] **Step 3: Make `tmux-pane-link` store the URL only**

In `roles/common/files/bin/tmux-pane-link`, update the header comment (lines 1–5) to describe a URL-only annotation. Change the opening comment first line from:

```bash
# Attach a label + URL annotation to the current tmux pane. The URL is
```

to:

```bash
# Attach a URL annotation to the current tmux pane. The URL is
```

Replace the positionals block (lines 60–61):

```bash
label="${positional[0]:-}"
url="${positional[1]:-}"
```

with:

```bash
url="${positional[0]:-}"
```

Remove the label-truncation and label-escaping block (current lines 79–86):

```bash
if [ "${#label}" -gt 64 ]; then
  label="${label:0:63}…"
fi
# Double `#` so tmux's format parser renders them literally; the URL is
# emitted as-is for terminal URL detection.
label="${label//#/##}"
url_escaped="${url//#/##}"
value="$label $url_escaped"
```

with:

```bash
# Double `#` so tmux's format parser renders them literally.
url_escaped="${url//#/##}"
value="$url_escaped"
```

(Leave the `write_pane_option "$pane" "@pane-link" "$value"` line, the URL validation, `--clear` handling, and `@pane-link-source` clearing unchanged.)

- [ ] **Step 4: Make `tmux-agent-worktree` emit and forward the URL only**

In `roles/common/files/bin/tmux-agent-worktree`, in `cached_pr_pane_link_for_path`, replace the jq output tail (current lines ~267–268):

```bash
      | [$display_ref, $html_url]
      | @tsv
```

with (keep the two `select(...)` guard lines above it unchanged):

```bash
      | $html_url
```

In `publish_cached_pr_pane_link_for_path`, change the local declaration (line ~275):

```bash
  local link display_ref url source
```

to:

```bash
  local link url source
```

Replace the TSV-split + guard block (lines ~287–296):

```bash
  IFS=$'\t' read -r display_ref url <<EOF
$link
EOF
  if [ -z "$display_ref" ] || [ -z "$url" ]; then
```

with:

```bash
  url="$link"
  if [ -z "$url" ]; then
```

(Leave the body of that `if` — the `@pane-link-source` clearing — unchanged.) Update the `tmux-pane-link` call (line ~299):

```bash
  if tmux-pane-link --pane "$pane_id" "$display_ref" "$url" >/dev/null 2>&1; then
```

to:

```bash
  if tmux-pane-link --pane "$pane_id" "$url" >/dev/null 2>&1; then
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/tmux-label-contract.sh`
Expected: PASS — ends with `tmux label contract checks complete`. Confirm the new "tmux-pane-link stores bare URL with no label" and "repo-start tmux writer publishes bare cached PR URL" cases both print `PASS`.

- [ ] **Step 6: Run the broader tmux test to confirm no regressions**

Run: `bash tests/tmux-agent-state.sh && bash tests/repo-tests-tmux-isolation.sh`
Expected: PASS for both (no failures printed).

- [ ] **Step 7: Commit**

```bash
git add roles/common/files/bin/tmux-pane-link roles/common/files/bin/tmux-agent-worktree tests/tmux-label-contract.sh
git commit -m "Store bare PR URL in pane link, drop display ref"
```

---

### Task 2: Render the PR link before the branch label

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf` (the `pane-border-format` line, ~line 124)
- Modify: `roles/linux/files/dotfiles/tmux.conf` (the `pane-border-format` line, ~line 116)
- Test: `tests/tmux-label-contract.sh`

**Interfaces:**
- Consumes: `@pane-link` (now URL-only, from Task 1), `@pane-label`, `@pane-last-error` pane options.
- Produces: a `pane-border-format` whose rendered order is `{color} {URL + space, if any} {branch label or cwd|host} {error}`.

- [ ] **Step 1: Write the failing test**

In `tests/tmux-label-contract.sh`, add an ordering helper near the other `assert_*` helpers:

```bash
assert_link_before_label() {
  local file="$1" name="$2" line before link_idx label_idx
  line="$(grep -F 'pane-border-format' "$file")" || fail_case "$name" "no pane-border-format in $file"
  before="${line%%@pane-link*}"
  link_idx=${#before}
  before="${line%%@pane-label*}"
  label_idx=${#before}
  if [ "$link_idx" -ge "$label_idx" ]; then
    fail_case "$name" "@pane-link ($link_idx) is not before @pane-label ($label_idx) in $file"
  fi
  pass_case "$name"
}
```

Add the assertions near the end of the file, before the final `printf 'tmux label contract checks complete\n'`:

```bash
assert_link_before_label "$REPO_ROOT/roles/macos/templates/dotfiles/tmux.conf" "macOS pane border renders PR link before label"
assert_link_before_label "$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf" "Linux pane border renders PR link before label"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/tmux-label-contract.sh`
Expected: FAIL with `@pane-link (N) is not before @pane-label (M)` — currently `@pane-label` precedes `@pane-link`.

- [ ] **Step 3: Reorder the macOS pane-border-format**

In `roles/macos/templates/dotfiles/tmux.conf`, replace the line:

```tmux
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #{?#{@pane-label},#{@pane-label},#{b:pane_current_path} | #{host_short}}#{?#{@pane-link}, #{@pane-link},}#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #[default],} '
```

with (the `@pane-link` block moves to just after the leading color+space and switches from a leading space to a trailing space):

```tmux
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #{?#{@pane-link},#{@pane-link} ,}#{?#{@pane-label},#{@pane-label},#{b:pane_current_path} | #{host_short}}#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #[default],} '
```

- [ ] **Step 4: Reorder the Linux pane-border-format**

In `roles/linux/files/dotfiles/tmux.conf`, the `pane-border-format` line is identical to the macOS one. Apply the exact same replacement as Step 3.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/tmux-label-contract.sh`
Expected: PASS — both new ordering cases print `PASS` and the script ends with `tmux label contract checks complete`.

- [ ] **Step 6: Commit**

```bash
git add roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf tests/tmux-label-contract.sh
git commit -m "Render PR link before branch label in pane border"
```

---

### Task 3: End-to-end verification and provision

**Files:** none (verification only).

There is no automated coverage that renders a live tmux border, so confirm the real behavior empirically and apply the changes to this machine.

- [ ] **Step 1: Apply the changes**

Run: `bin/provision --diff`
Expected: diff shows the updated `tmux-pane-link`, `tmux-agent-worktree`, and the `pane-border-format` line in `~/.config`/tmux destinations; no unrelated changes. Then run `bin/provision` to apply.

- [ ] **Step 2: Reload tmux and confirm the live border**

Run: `tmux source-file ~/.tmux.conf` (or the provisioned tmux.conf path), then, in a pane associated with a branch that has an open PR in the PR-status cache, observe the pane border.
Expected: the border shows the bare PR URL **first** (no `gh#`/`fj#` prefix), followed by the branch/repo label, then any error indicator. The full URL is visible and clickable even on a narrow pane.

- [ ] **Step 3: Confirm the no-PR and clear paths**

Expected: a pane with no associated PR shows only the branch/repo label (unchanged). After `tmux-pane-link --clear` (or a `tmux-agent-worktree clear`), the URL disappears from the border.

- [ ] **Step 4: Run the full local test suite touched by this change**

Run: `bash tests/tmux-label-contract.sh && bash tests/tmux-agent-state.sh && bash tests/repo-tests-tmux-isolation.sh && bash tests/ci-test-inventory.sh`
Expected: all PASS; `ci-test-inventory.sh` reports no unregistered tests.
