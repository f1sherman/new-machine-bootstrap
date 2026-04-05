# Session Context Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve session context visibility with a `/catchup` skill, tmux window/status bar fixes, and ccstatusline simplification.

**Architecture:** Four independent changes sharing no code dependencies. Each task is self-contained and can be implemented in any order. All changes are deployed via `bin/provision` (Ansible).

**Tech Stack:** Bash (tmux-host-tag script), Markdown (skill), JSON (ccstatusline), Ansible YAML (tasks), tmux config

---

### Task 1: Simplify ccstatusline

**Files:**
- Modify: `roles/common/files/config/ccstatusline/settings.json`

- [ ] **Step 1: Write a test script to verify the current config has 4 components**

Create `tmp/test-ccstatusline.sh`:

```bash
#!/usr/bin/env bash
set -e

config="roles/common/files/config/ccstatusline/settings.json"

count=$(jq '.lines[0] | length' "$config")
if [ "$count" -ne 2 ]; then
  echo "FAIL: Expected 2 components in lines[0], got $count"
  exit 1
fi

# Verify only model and context-percentage-usable remain
types=$(jq -r '.lines[0][].type' "$config" | sort)
expected=$'context-percentage-usable\nmodel'
if [ "$types" != "$expected" ]; then
  echo "FAIL: Expected types 'model' and 'context-percentage-usable', got:"
  echo "$types"
  exit 1
fi

# Verify powerline is still enabled
powerline=$(jq '.powerline.enabled' "$config")
if [ "$powerline" != "true" ]; then
  echo "FAIL: Powerline should be enabled, got $powerline"
  exit 1
fi

echo "PASS: ccstatusline config has 2 components with powerline enabled"
```

- [ ] **Step 2: Run the test to verify it fails (current config has 4 components)**

Run: `bash tmp/test-ccstatusline.sh`
Expected: `FAIL: Expected 2 components in lines[0], got 4`

- [ ] **Step 3: Update the ccstatusline config**

Replace the contents of `roles/common/files/config/ccstatusline/settings.json` with:

```json
{
  "version": 3,
  "lines": [
    [
      {
        "id": "1",
        "type": "model",
        "color": "cyan"
      },
      {
        "id": "2",
        "type": "context-percentage-usable",
        "color": "brightBlack",
        "metadata": {
          "inverse": "true"
        }
      }
    ],
    [],
    []
  ],
  "flexMode": "full-minus-40",
  "compactThreshold": 60,
  "colorLevel": 2,
  "defaultPadding": " ",
  "inheritSeparatorColors": false,
  "globalBold": false,
  "powerline": {
    "enabled": true,
    "separators": [
      "\ue0b1"
    ],
    "separatorInvertBackground": [
      false
    ],
    "startCaps": [],
    "endCaps": [],
    "theme": "nord-aurora",
    "autoAlign": false
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tmp/test-ccstatusline.sh`
Expected: `PASS: ccstatusline config has 2 components with powerline enabled`

- [ ] **Step 5: Commit**

```bash
git add roles/common/files/config/ccstatusline/settings.json
git commit -m "Simplify ccstatusline to model + context percentage"
```

---

### Task 2: Fix tmux window names

**Files:**
- Modify: `roles/macos/templates/dotfiles/tmux.conf:69`
- Modify: `roles/linux/files/dotfiles/tmux.conf:67`

- [ ] **Step 1: Write a test script to verify allow-rename is set in both configs**

Create `tmp/test-tmux-allow-rename.sh`:

```bash
#!/usr/bin/env bash
set -e

fail=0

for config in roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf; do
  if ! grep -q 'set -g allow-rename off' "$config"; then
    echo "FAIL: $config missing 'set -g allow-rename off'"
    fail=1
  else
    echo "PASS: $config has allow-rename off"
  fi
done

exit $fail
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tmp/test-tmux-allow-rename.sh`
Expected: Both configs report FAIL

- [ ] **Step 3: Add allow-rename off to macOS tmux config**

In `roles/macos/templates/dotfiles/tmux.conf`, add after line 69 (`setw -g automatic-rename`):

```
set -g allow-rename off
```

- [ ] **Step 4: Add allow-rename off to Linux tmux config**

In `roles/linux/files/dotfiles/tmux.conf`, add after line 67 (`setw -g automatic-rename`):

```
set -g allow-rename off
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tmp/test-tmux-allow-rename.sh`
Expected: Both configs report PASS

- [ ] **Step 6: Commit**

```bash
git add roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git commit -m "Fix tmux window names showing Claude Code version number"
```

---

### Task 3: Add tagged hostname to tmux status bar

**Files:**
- Create: `roles/common/files/bin/tmux-host-tag`
- Modify: `roles/macos/templates/dotfiles/tmux.conf:54-55`
- Modify: `roles/linux/files/dotfiles/tmux.conf:52-53`
- Modify: `roles/common/tasks/main.yml:196` (after tmux-switch-session install task)

- [ ] **Step 1: Research the correct DevPod environment variable**

Run inside a DevPod (or check DevPod documentation) to determine which environment variable identifies a DevPod environment. Check for `DEVPOD_NAME`, `DEVPOD`, `DEVPOD_WORKSPACE_ID`, or similar. Update the script in the next step accordingly.

If no DevPod is available, use `DEVPOD_WORKSPACE_ID` as a reasonable default (it's documented in DevPod's environment variables) and use the hostname as the display name.

- [ ] **Step 2: Write a test script for the tmux-host-tag script**

Create `tmp/test-tmux-host-tag.sh`:

```bash
#!/usr/bin/env bash
set -e

script="roles/common/files/bin/tmux-host-tag"

if [ ! -x "$script" ]; then
  echo "FAIL: $script does not exist or is not executable"
  exit 1
fi

# Test local (no special env vars)
result=$(env -i HOME="$HOME" PATH="$PATH" "$script")
if [[ "$result" != "[local] "* ]]; then
  echo "FAIL: Expected '[local] ...' for default, got: $result"
  exit 1
fi
echo "PASS: Local tag works: $result"

# Test codespace
result=$(CODESPACES=true CODESPACE_NAME="fluffy-robot-abc" "$script")
if [ "$result" != "[cs] fluffy-robot-abc" ]; then
  echo "FAIL: Expected '[cs] fluffy-robot-abc', got: $result"
  exit 1
fi
echo "PASS: Codespace tag works: $result"

# Test SSH
result=$(env -i HOME="$HOME" PATH="$PATH" SSH_CONNECTION="1.2.3.4 1234 5.6.7.8 22" "$script")
if [[ "$result" != "[ssh] "* ]]; then
  echo "FAIL: Expected '[ssh] ...' for SSH, got: $result"
  exit 1
fi
echo "PASS: SSH tag works: $result"

echo "ALL PASS"
```

- [ ] **Step 3: Run the test to verify it fails (script doesn't exist)**

Run: `bash tmp/test-tmux-host-tag.sh`
Expected: `FAIL: roles/common/files/bin/tmux-host-tag does not exist or is not executable`

- [ ] **Step 4: Create the tmux-host-tag script**

Create `roles/common/files/bin/tmux-host-tag`:

```bash
#!/usr/bin/env bash
if [ -n "$CODESPACES" ]; then
  echo "[cs] ${CODESPACE_NAME:-$(hostname -s)}"
elif [ -n "$DEVPOD_WORKSPACE_ID" ]; then
  echo "[devpod] ${DEVPOD_WORKSPACE_ID}"
elif [ -n "$SSH_CONNECTION" ]; then
  echo "[ssh] $(hostname -s)"
else
  echo "[local] $(hostname -s)"
fi
```

Make it executable: `chmod +x roles/common/files/bin/tmux-host-tag`

Note: The DevPod env var (`DEVPOD_WORKSPACE_ID`) should be verified per Step 1. Adjust if a different variable is more appropriate.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tmp/test-tmux-host-tag.sh`
Expected: `ALL PASS`

- [ ] **Step 6: Update macOS tmux status-left**

In `roles/macos/templates/dotfiles/tmux.conf`, replace lines 54-55:

Old:
```
set -g status-left-length 60
set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]'
```

New:
```
set -g status-left-length 80
set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]#(tmux-host-tag)'
```

- [ ] **Step 7: Update Linux tmux status-left**

In `roles/linux/files/dotfiles/tmux.conf`, replace lines 52-53:

Old:
```
set -g status-left-length 80
set -g status-left '#[fg=cyan]#(echo "${CODESPACE_NAME:-$(hostname -s)}") #[fg=white]| #[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]'
```

New:
```
set -g status-left-length 80
set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]#(tmux-host-tag)'
```

- [ ] **Step 8: Add Ansible task to install tmux-host-tag**

In `roles/common/tasks/main.yml`, add after the "Install tmux-switch-session script" task (after line 196):

```yaml
- name: Install tmux-host-tag script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/tmux-host-tag'
    src: '{{ playbook_dir }}/roles/common/files/bin/tmux-host-tag'
    mode: 0755
```

- [ ] **Step 9: Verify Ansible syntax**

Run: `bin/provision --check --diff 2>&1 | head -50`
Expected: No syntax errors. The tmux config and tmux-host-tag tasks should show as "changed".

- [ ] **Step 10: Commit**

```bash
git add roles/common/files/bin/tmux-host-tag roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf roles/common/tasks/main.yml
git commit -m "Add tagged hostname to tmux status bar"
```

---

### Task 4: Create /catchup skill

**Files:**
- Create: `roles/common/files/config/skills/common/catchup/SKILL.md`

- [ ] **Step 1: Write a test script to verify the skill file exists and has correct frontmatter**

Create `tmp/test-catchup-skill.sh`:

```bash
#!/usr/bin/env bash
set -e

skill="roles/common/files/config/skills/common/catchup/SKILL.md"

if [ ! -f "$skill" ]; then
  echo "FAIL: $skill does not exist"
  exit 1
fi

# Check frontmatter has name field
if ! grep -q '^name: catchup' "$skill"; then
  echo "FAIL: Missing 'name: catchup' in frontmatter"
  exit 1
fi

# Check frontmatter has description
if ! grep -q '^description:' "$skill"; then
  echo "FAIL: Missing description in frontmatter"
  exit 1
fi

# Check body mentions the 3 summary elements
for keyword in "working on" "left off" "next"; do
  if ! grep -qi "$keyword" "$skill"; then
    echo "FAIL: Skill body should reference '$keyword'"
    exit 1
  fi
done

echo "PASS: catchup skill exists with correct frontmatter and body"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tmp/test-catchup-skill.sh`
Expected: `FAIL: roles/common/files/config/skills/common/catchup/SKILL.md does not exist`

- [ ] **Step 3: Create the catchup skill**

Create directory and file `roles/common/files/config/skills/common/catchup/SKILL.md`:

```markdown
---
name: catchup
description: >
  Use when the user wants a quick summary of the current session context.
  Use when switching between sessions, losing track, or needing a refresher
  on what's happening and what's next.
---

# Session Catchup

Summarize the current session in 2-3 sentences. Cover:

1. **What we're working on** — the goal or task
2. **Where we left off** — the last completed step or action
3. **What's next** — the immediate next step

Use tasks (if any exist), recent tool calls, active plans, and conversation history to derive the summary. Be direct — no preamble, no filler.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tmp/test-catchup-skill.sh`
Expected: `PASS: catchup skill exists with correct frontmatter and body`

- [ ] **Step 5: Verify the skill will be installed by existing Ansible tasks**

The existing task "Install common skills to ~/.claude/skills" (line 777-782 of `roles/common/tasks/main.yml`) copies the entire `roles/common/files/config/skills/common/` directory. The new `catchup/` subdirectory will be included automatically. No new Ansible task needed.

Verify: `ls roles/common/files/config/skills/common/catchup/SKILL.md`
Expected: File exists

- [ ] **Step 6: Commit**

```bash
git add roles/common/files/config/skills/common/catchup/SKILL.md
git commit -m "Add /catchup skill for quick session context summary"
```

---

### Task 5: Provision and verify

- [ ] **Step 1: Run full provisioning**

Run: `bin/provision`
Expected: Completes successfully. New/changed tasks include:
- "Install tmux-host-tag script" — changed
- "Install ccstatusline widget configuration" — changed
- Tmux config template — changed
- Common skills copy — changed

- [ ] **Step 2: Verify ccstatusline is simplified**

Open a new Claude Code session (or restart current one). The statusline should show only model and context percentage with a powerline separator, not the full 4-component display.

- [ ] **Step 3: Verify tmux window name**

In a tmux window running Claude Code, the window name should show `claude` (or the actual binary name), not a version number like `2.1.92`. Check with: `tmux list-windows -F '#{window_name}'`

- [ ] **Step 4: Verify tagged hostname in status bar**

The tmux status bar left side should show: `(branch) dirname [local] hostname`. Verify visually or with: `tmux display-message -p '#{status-left}'`

- [ ] **Step 5: Verify /catchup skill is installed**

Run: `ls ~/.claude/skills/catchup/SKILL.md`
Expected: File exists

- [ ] **Step 6: Clean up test scripts**

```bash
rm -f tmp/test-ccstatusline.sh tmp/test-tmux-allow-rename.sh tmp/test-tmux-host-tag.sh tmp/test-catchup-skill.sh
```

- [ ] **Step 7: Commit any remaining changes (if any)**

If provisioning produced any changes that need committing, commit them. Otherwise, this step is a no-op.
