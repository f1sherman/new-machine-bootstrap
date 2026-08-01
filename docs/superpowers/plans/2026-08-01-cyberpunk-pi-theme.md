# Cyberpunk 2077 Pi Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and provision one optional, balanced Night City Pi theme without changing the active theme.

**Architecture:** Store the complete Pi theme JSON with the common role's managed Pi files. Add two Ansible tasks that create the global theme directory and copy the theme, plus a focused contract test that validates the theme schema contract and provisioning declarations.

**Tech Stack:** Pi theme JSON, Ansible YAML, Bash, jq, yq, GitHub Actions.

## Global Constraints

- The managed theme name is exactly `cyberpunk-2077`.
- Provision the theme to `~/.pi/agent/themes/cyberpunk-2077.json`.
- Do not modify `~/.pi/agent/settings.json` or select a default theme.
- Add only one theme variant. Do not add custom UI behavior, icons, labels, or decorations.
- Keep normal prose and most syntax colors neutral. Use neon colors for structure and state.
- Prioritize contrast and readability over visual fidelity.

---

### Task 1: Add the managed Cyberpunk Pi theme

**Files:**
- Create: `roles/common/files/pi/themes/cyberpunk-2077.json`
- Create: `tests/pi-cyberpunk-theme.sh`
- Modify: `roles/common/tasks/main.yml`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: Pi's documented theme schema and `ansible_facts['user_dir']` from the common role.
- Produces: a valid theme named `cyberpunk-2077` at `{{ ansible_facts['user_dir'] }}/.pi/agent/themes/cyberpunk-2077.json`.

- [ ] **Step 1: Write the failing theme contract test**

Create executable `tests/pi-cyberpunk-theme.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
theme_file="$repo_root/roles/common/files/pi/themes/cyberpunk-2077.json"
tasks_file="$repo_root/roles/common/tasks/main.yml"

if command -v yq >/dev/null 2>&1; then
  yq_bin="$(command -v yq)"
elif [ -x "$HOME/.local/bin/yq" ]; then
  yq_bin="$HOME/.local/bin/yq"
else
  printf 'FAIL  Cyberpunk Pi theme contract: missing yq\n' >&2
  exit 1
fi

required_colors='[
  "accent", "bashMode", "border", "borderAccent", "borderMuted", "customMessageBg",
  "customMessageLabel", "customMessageText", "dim", "error", "mdCode", "mdCodeBlock",
  "mdCodeBlockBorder", "mdHeading", "mdHr", "mdLink", "mdLinkUrl", "mdListBullet",
  "mdQuote", "mdQuoteBorder", "muted", "selectedBg", "success", "syntaxComment",
  "syntaxFunction", "syntaxKeyword", "syntaxNumber", "syntaxOperator", "syntaxPunctuation",
  "syntaxString", "syntaxType", "syntaxVariable", "text", "thinkingHigh", "thinkingLow",
  "thinkingMax", "thinkingMedium", "thinkingMinimal", "thinkingOff", "thinkingText",
  "thinkingXhigh", "toolDiffAdded", "toolDiffContext", "toolDiffRemoved", "toolErrorBg",
  "toolOutput", "toolPendingBg", "toolSuccessBg", "toolTitle", "userMessageBg",
  "userMessageText", "warning"
]'

jq -e --argjson required "$required_colors" '
  .name == "cyberpunk-2077" and
  ((.colors | keys | sort) == ($required | sort)) and
  (.vars | type == "object") and
  (. as $theme | all(.colors[];
    . as $value |
    type == "string" and
    (. == "" or test("^#[0-9A-Fa-f]{6}$") or ($theme.vars | has($value)))
  ))
' "$theme_file" >/dev/null

"$yq_bin" -o=json '.' "$tasks_file" | jq -e '
  any(.[];
    .name == "Create pi-coding-agent global themes directory" and
    .file.path == "{{ ansible_facts[\u0027user_dir\u0027] }}/.pi/agent/themes" and
    .file.state == "directory" and .file.mode == "0755"
  ) and
  any(.[];
    .name == "Install Cyberpunk 2077 pi-coding-agent theme" and
    .copy.src == "pi/themes/cyberpunk-2077.json" and
    .copy.dest == "{{ ansible_facts[\u0027user_dir\u0027] }}/.pi/agent/themes/cyberpunk-2077.json" and
    .copy.mode == "0644"
  )
' >/dev/null

if rg -n 'theme[^[:alnum:]]+cyberpunk-2077' "$tasks_file" >/dev/null; then
  printf 'FAIL  Cyberpunk theme must remain optional\n' >&2
  exit 1
fi

printf 'PASS  Cyberpunk Pi theme contract\n'
```

- [ ] **Step 2: Run the contract test and confirm it fails**

Run:

```bash
bash tests/pi-cyberpunk-theme.sh
```

Expected: nonzero exit because the theme file and Ansible tasks do not exist.

- [ ] **Step 3: Create the theme JSON**

Create `roles/common/files/pi/themes/cyberpunk-2077.json` with Pi's schema URL, the exact theme name, all required tokens, and this palette hierarchy:

```json
{
  "night": "#0b0f1a",
  "panel": "#111827",
  "panelRaised": "#172033",
  "panelSuccess": "#102927",
  "panelError": "#301820",
  "cyan": "#00f0ff",
  "cyanSoft": "#64d8e8",
  "yellow": "#fcee0a",
  "magenta": "#ff2a6d",
  "red": "#ff5c57",
  "green": "#5fffb0",
  "text": "#e6edf3",
  "muted": "#8ba3b8",
  "dim": "#60758a",
  "borderMuted": "#34465a"
}
```

Map neutral text to prose and tool output. Use cyan for accents, borders, links, types, and code. Use yellow for warnings, headings, variables, and Bash mode. Use green for success, strings, and added diffs. Use red for errors and removed diffs. Use magenta only for custom labels, numbers, and high thinking levels. Progress thinking borders from `borderMuted` through `cyanSoft`, `cyan`, and `magenta`.

- [ ] **Step 4: Add common-role provisioning tasks**

After `Create pi-coding-agent global extensions directory`, add:

```yaml
- name: Create pi-coding-agent global themes directory
  file:
    path: "{{ ansible_facts['user_dir'] }}/.pi/agent/themes"
    state: directory
    mode: '0755'

- name: Install Cyberpunk 2077 pi-coding-agent theme
  copy:
    src: pi/themes/cyberpunk-2077.json
    dest: "{{ ansible_facts['user_dir'] }}/.pi/agent/themes/cyberpunk-2077.json"
    mode: '0644'
```

Do not add or change a Pi settings task.

- [ ] **Step 5: Run the focused contract test**

Run:

```bash
bash tests/pi-cyberpunk-theme.sh
```

Expected: `PASS  Cyberpunk Pi theme contract` and exit status `0`.

- [ ] **Step 6: Register the contract test in CI**

Add this step near the other Pi verification steps in `.github/workflows/integration-test.yml`:

```yaml
      - name: Verify Cyberpunk Pi theme
        run: bash tests/pi-cyberpunk-theme.sh
```

- [ ] **Step 7: Run repository validation**

Run:

```bash
bash tests/pi-cyberpunk-theme.sh
bash tests/ci-test-inventory.sh
ansible-playbook playbook.yml --syntax-check
bin/provision --check
```

Expected: all commands exit `0`. If check mode reports an unrelated host-state failure, record the exact failure and confirm the theme tasks with the contract test and syntax check.

- [ ] **Step 8: Provision and verify the installed theme**

Run:

```bash
bin/provision
cmp roles/common/files/pi/themes/cyberpunk-2077.json "$HOME/.pi/agent/themes/cyberpunk-2077.json"
jq -e '.name == "cyberpunk-2077"' "$HOME/.pi/agent/themes/cyberpunk-2077.json"
pi --theme cyberpunk-2077 --help >/dev/null
```

Expected: provisioning exits `0`, `cmp` exits `0`, jq prints `true`, and Pi accepts the installed theme without a theme-loading error. The active Pi settings remain unchanged.

- [ ] **Step 9: Commit the implementation**

Use the `z-commit` skill to commit:

```text
roles/common/files/pi/themes/cyberpunk-2077.json
roles/common/tasks/main.yml
tests/pi-cyberpunk-theme.sh
.github/workflows/integration-test.yml
docs/superpowers/plans/2026-08-01-cyberpunk-pi-theme.md
```

Use the imperative commit message `Add optional Cyberpunk Pi theme`.
