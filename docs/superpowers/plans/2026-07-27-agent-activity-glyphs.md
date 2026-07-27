# Agent Activity Glyphs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render tmux agent activity as `⏳` while working and `💬` while waiting for user input.

**Architecture:** Keep the existing semantic `working` and `waiting` state contract unchanged. Change only the renderer-owned mapping in `tmux-indicator-glyphs`, with the existing shell contract suite exercising direct, local, remote, and combined rendering paths.

**Tech Stack:** Bash, tmux formatting, shell contract tests, Ansible provisioning

## Global Constraints

- `working` maps to `⏳`.
- `waiting` maps to `💬`.
- Existing pane options, remote title transport, PR-state indicators, and panes without agent state remain unchanged.
- Unknown or absent activity values continue to emit no activity glyph.
- Historical design documents remain unchanged.

---

### Task 1: Remap agent activity glyphs

**Files:**
- Modify: `tests/tmux-label-contract.sh:176-177,536,710,716,722`
- Modify: `roles/common/files/bin/tmux-indicator-glyphs:9-13`

**Interfaces:**
- Consumes: positional argument 1 as `working`, `waiting`, empty, or an unknown semantic activity state; positional argument 2 as the existing PR state.
- Produces: a rendered tmux indicator prefix with a trailing space when any known indicator exists; `⏳` for working and `💬` for waiting.

- [ ] **Step 1: Write the failing behavioral assertions**

Change the activity expectations in `tests/tmux-label-contract.sh` while leaving production code untouched:

```bash
assert_equals "$("$GLYPHS" working approved)" '⏳#[fg=#b5bd68]● ' "indicator glyphs render working+approved"
assert_equals "$("$GLYPHS" waiting "")" "💬 " "indicator glyphs render waiting only"
```

Update every downstream literal in the same test that represents the helper's consumer-visible output:

```bash
'set-option -wq -t @1 @window-indicators ⏳#[fg=#8957e5]● '
"set-option -wq -t @1 @window-indicators ⏳#[fg=#808080]● "
"set-option -wq -t @1 @window-indicators 💬#[fg=#b5bd68]● "
"set-option -wq -t @1 @window-indicators 💬 "
```

These assertions catch either semantic branch retaining or regressing to the wrong glyph. They execute the real helper and rendering pipeline rather than inspecting source text.

- [ ] **Step 2: Run the contract suite and verify RED**

Run:

```bash
tests/tmux-label-contract.sh
```

Expected: nonzero exit at `indicator glyphs render working+approved`, reporting expected `⏳...` but actual `🤖...`. The failure must be caused by the unchanged production mapping.

- [ ] **Step 3: Implement the minimal mapping change**

In `roles/common/files/bin/tmux-indicator-glyphs`, replace only the activity branches:

```bash
case "$activity" in
  working) out+="⏳" ;;
  waiting) out+="💬" ;;
esac
```

Do not alter state names, PR mappings, output spacing, or unknown-value handling.

- [ ] **Step 4: Run the contract suite and verify GREEN**

Run:

```bash
tests/tmux-label-contract.sh
```

Expected: exit 0; all direct glyph, remote marker, local pane state, PR combination, and tmux configuration checks pass.

- [ ] **Step 5: Review the focused diff and commit**

Run:

```bash
git diff --check
git diff -- roles/common/files/bin/tmux-indicator-glyphs tests/tmux-label-contract.sh
```

Confirm only the two mappings and corresponding expected outputs changed. Commit both files with an imperative message explaining the clearer status semantics.

- [ ] **Step 6: Provision the managed files**

Run:

```bash
bin/provision
```

Expected: exit 0 and the managed `tmux-indicator-glyphs` is installed without unrelated provisioning failures.

- [ ] **Step 7: Verify the deployed helper and live state transitions**

Run direct deployed-helper checks:

```bash
test "$(~/.local/bin/tmux-indicator-glyphs working '')" = "⏳ "
test "$(~/.local/bin/tmux-indicator-glyphs waiting '')" = "💬 "
```

In a tmux pane, set each semantic state and refresh the window label:

```bash
tmux set-option -pt "$TMUX_PANE" @agent_activity working
tmux-window-label "$TMUX_PANE"
tmux set-option -pt "$TMUX_PANE" @agent_activity waiting
tmux-window-label "$TMUX_PANE"
```

Expected: the tab renders `⏳` for working and then `💬` for waiting. Leave the activity producer to restore the pane's real state on the next session event.
