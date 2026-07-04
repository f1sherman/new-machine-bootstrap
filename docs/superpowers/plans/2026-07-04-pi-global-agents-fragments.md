# Pi Global AGENTS Fragments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an NMB-owned, provider-neutral `~/.pi/agent/AGENTS.md.d` fragment assembly point for Pi global instructions.

**Architecture:** Mirror the existing Claude global instruction fragment pattern for Pi: create the fragment directory, install a generic base fragment, and assemble sorted fragments into `~/.pi/agent/AGENTS.md`. Keep repo-start callbacks unchanged because they already provide the downstream hook needed by HNP.

**Tech Stack:** Ansible `file`, `copy`, and `command` tasks; a small Bash helper for assembling sorted Pi AGENTS fragments; shell verification with a behavior test and Ansible syntax checking.

## Global Constraints

- NMB must not mention HNP, Forgejo, GitHub PR routing, or `pull-request` in the new Pi base fragment.
- Pi global context file path is `~/.pi/agent/AGENTS.md`.
- Downstream provisioners must be able to drop sorted fragments into `~/.pi/agent/AGENTS.md.d`.
- Specs and plans are committed under `docs/superpowers/` unless ignored.

---

## File structure

- Create `roles/common/files/pi/AGENTS.md.d/00-base.md`: generic Pi global instruction fragment. Its job is to document that downstream fragments may add workflow-specific guidance; it must not name HNP or personal PR skills.
- Create `roles/common/files/bin/pi-agent-assemble-agents`: generic helper that concatenates sorted fragment files into `~/.pi/agent/AGENTS.md` with mode `0600`.
- Modify `roles/common/tasks/main.yml`: install the helper, add Pi global AGENTS directory creation, install the base fragment, and run the helper near the existing Pi setup tasks.
- Create `tests/pi-agent-assemble-agents.sh`: behavior test for sorted assembly, output mode, and base-fragment neutrality.

### Task 1: Add neutral Pi global AGENTS assembly

**Files:**
- Create: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Create: `roles/common/files/bin/pi-agent-assemble-agents`
- Create: `tests/pi-agent-assemble-agents.sh`
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: Ansible facts `ansible_facts['user_dir']` and `playbook_dir`, consistent with nearby common-role tasks.
- Produces: `~/.pi/agent/AGENTS.md.d/00-base.md`, a reusable `pi-agent-assemble-agents` helper for downstream reassembly, and assembled `~/.pi/agent/AGENTS.md` for Pi to load globally.

- [ ] **Step 1: Add the neutral base fragment**

Create `roles/common/files/pi/AGENTS.md.d/00-base.md` with exactly:

```markdown
User name: Brian. Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

* Workspace: `~/projects/`
* Bias toward action. Only ask user when you can't do it yourself.
* Follow repository-local instructions first. Global Pi fragments provide defaults only when repo instructions are silent.
* Downstream provisioning may add workflow-specific fragments under `~/.pi/agent/AGENTS.md.d/`; honor those fragments when present.
* Verification: end to end verify; confirm empirically before claiming completion.
```

- [ ] **Step 2: Create the reusable assembly helper**

Create `roles/common/files/bin/pi-agent-assemble-agents` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

agent_dir="${PI_AGENT_DIR:-$HOME/.pi/agent}"
fragment_dir="$agent_dir/AGENTS.md.d"
output_file="$agent_dir/AGENTS.md"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

if [[ -d "$fragment_dir" ]]; then
  find "$fragment_dir" -maxdepth 1 -type f | sort | while IFS= read -r fragment; do
    cat "$fragment"
    printf '\n'
  done >"$tmp_file"
else
  : >"$tmp_file"
fi

install -m 0600 "$tmp_file" "$output_file"
```

- [ ] **Step 3: Insert Pi AGENTS tasks into `roles/common/tasks/main.yml`**

Add `pi-agent-assemble-agents` to the existing `Install worktree helpers` loop with mode `0755`. Then place these tasks after the existing `Create pi-coding-agent global extensions directory` task and before `Install managed pi-coding-agent keybindings`:

```yaml
- name: Create pi-coding-agent global AGENTS fragment directory
  file:
    path: "{{ ansible_facts['user_dir'] }}/.pi/agent/AGENTS.md.d"
    state: directory
    mode: '0700'

- name: Install base pi-coding-agent global AGENTS fragment
  copy:
    src: pi/AGENTS.md.d/00-base.md
    dest: "{{ ansible_facts['user_dir'] }}/.pi/agent/AGENTS.md.d/00-base.md"
    mode: '0600'

- name: Assemble pi-coding-agent global AGENTS.md from fragments
  command: "{{ ansible_facts['user_dir'] }}/.local/bin/pi-agent-assemble-agents"
  environment:
    HOME: "{{ ansible_facts['user_dir'] }}"
  changed_when: false
```

- [ ] **Step 4: Add and run the helper behavior test**

Create `tests/pi-agent-assemble-agents.sh` to verify sorted assembly, mode `0600`, and base-fragment neutrality. Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
chmod +x tests/pi-agent-assemble-agents.sh
bash tests/pi-agent-assemble-agents.sh
```

Expected: output includes `pi AGENTS assembly checks complete`.

- [ ] **Step 5: Verify the fragment is neutral**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
if rg -n 'HNP|home-network|Forgejo|GitHub PR routing|pull-request' roles/common/files/pi/AGENTS.md.d/00-base.md; then
  echo 'FAIL: Pi base fragment contains downstream-specific guidance'
  exit 1
fi
```

Expected: no output and exit status `0`.

- [ ] **Step 6: Verify Ansible syntax**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
ansible-playbook playbook.yml --syntax-check
```

Expected: syntax check succeeds.

- [ ] **Step 7: Commit implementation**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
~/.pi/agent/skills/commit/commit.sh -m "Add Pi global AGENTS fragment assembly" \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/bin/pi-agent-assemble-agents \
  roles/common/tasks/main.yml \
  tests/pi-agent-assemble-agents.sh
```

Expected: one implementation commit.

## Final verification

- [ ] Run targeted grep verification again:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
rg -n 'AGENTS.md.d|Assemble pi-coding-agent global AGENTS.md' roles/common/tasks/main.yml
```

Expected: matches for the new Pi fragment directory and assemble task.

- [ ] Run full relevant checks:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
ansible-playbook playbook.yml --syntax-check
```

Expected: syntax check succeeds.

## Plan self-review

- Spec coverage: NMB creates generic Pi AGENTS fragment assembly and avoids HNP-specific content.
- Placeholder scan: no placeholders remain.
- Type consistency: Ansible paths and file names are consistent across tasks and verification.
