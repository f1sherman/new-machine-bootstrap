# Pi Newline Keybinding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage pi's `Ctrl+N` newline fallback from Ansible.

**Architecture:** Add one common-role task near existing pi-coding-agent configuration tasks. The task fully manages `~/.pi/agent/keybindings.json` with only `shift+enter` and `ctrl+n` bound to newline.

**Tech Stack:** Ansible YAML, JSON, jq for verification.

## Global Constraints

- Do not change tmux configuration.
- Do not include `ctrl+j`; tmux uses it for pane navigation.
- Do not add a tautological CI test that only asserts source literals.

---

### Task 1: Manage pi keybindings JSON

**Files:**
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: existing `ansible_facts['user_dir']` use in the common role.
- Produces: deployed `{{ ansible_facts['user_dir'] }}/.pi/agent/keybindings.json`.

- [ ] **Step 1: Add the common-role task**

Insert after `Create pi-coding-agent global extensions directory` and before `Install managed pi-coding-agent hooks`:

```yaml
- name: Install managed pi-coding-agent keybindings
  copy:
    dest: "{{ ansible_facts['user_dir'] }}/.pi/agent/keybindings.json"
    mode: '0644'
    content: |
      {
        "tui.input.newLine": ["shift+enter", "ctrl+n"]
      }
```

- [ ] **Step 2: Verify YAML syntax**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file("roles/common/tasks/main.yml"); puts "yaml ok"'
```

Expected: `yaml ok`.

- [ ] **Step 3: Verify managed JSON content parses**

Extract the content block into jq:

```bash
ruby -e '
text = File.read("roles/common/tasks/main.yml")
match = text.match(/content: \|\n((?:      .*\n)+)/)
abort "missing content block" unless match
json = match[1].lines.map { |line| line.sub(/^      /, "") }.join
print json
' | jq -e '."tui.input.newLine" == ["shift+enter", "ctrl+n"]'
```

Expected: `true`.

- [ ] **Step 4: Run local provision or check mode**

Run:

```bash
bin/provision --check
```

Expected: completes without errors. If check mode is blocked by an unrelated pre-existing task, capture the failure and run a narrower syntax validation instead.

- [ ] **Step 5: Commit implementation**

```bash
git add roles/common/tasks/main.yml docs/superpowers/specs/2026-07-03-pi-newline-keybinding-design.md docs/superpowers/plans/2026-07-03-pi-newline-keybinding.md
git commit -m "Manage pi newline keybinding"
```
