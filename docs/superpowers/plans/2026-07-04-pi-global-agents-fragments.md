# Pi Global AGENTS Fragments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an NMB-owned, provider-neutral `~/.pi/agent/AGENTS.md.d` fragment assembly point for Pi global instructions.

**Architecture:** Mirror the existing Claude global instruction fragment pattern for Pi: create the fragment directory, install a generic base fragment, and assemble sorted fragments into `~/.pi/agent/AGENTS.md`. Keep repo-start callbacks unchanged because they already provide the downstream hook needed by HNP.

**Tech Stack:** Ansible `file`, `copy`, and `assemble` tasks; shell/Ruby-free verification with repo grep and Ansible syntax checking.

## Global Constraints

- NMB must not mention HNP, Forgejo, GitHub PR routing, or `pull-request` in the new Pi base fragment.
- Pi global context file path is `~/.pi/agent/AGENTS.md`.
- Downstream provisioners must be able to drop sorted fragments into `~/.pi/agent/AGENTS.md.d`.
- Specs and plans are committed under `docs/superpowers/` unless ignored.

---

## File structure

- Create `roles/common/files/pi/AGENTS.md.d/00-base.md`: generic Pi global instruction fragment. Its job is to document that downstream fragments may add workflow-specific guidance; it must not name HNP or personal PR skills.
- Modify `roles/common/tasks/main.yml`: add Pi global AGENTS directory creation and assembly near the existing Pi setup tasks, before Pi sessions need extensions/skills.
- Optionally modify `tests/pi-managed-hooks.sh` only if implementation touches managed hooks; current plan does not.

### Task 1: Add neutral Pi global AGENTS assembly

**Files:**
- Create: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: Ansible facts `ansible_facts['user_dir']` and `playbook_dir`, consistent with nearby common-role tasks.
- Produces: `~/.pi/agent/AGENTS.md.d/00-base.md` and assembled `~/.pi/agent/AGENTS.md` for Pi to load globally.

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

- [ ] **Step 2: Insert Pi AGENTS tasks into `roles/common/tasks/main.yml`**

Place these tasks after the existing `Create pi-coding-agent global extensions directory` task and before `Install managed pi-coding-agent keybindings`:

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
  assemble:
    src: "{{ ansible_facts['user_dir'] }}/.pi/agent/AGENTS.md.d"
    dest: "{{ ansible_facts['user_dir'] }}/.pi/agent/AGENTS.md"
    mode: '0600'
```

- [ ] **Step 3: Verify the fragment is neutral**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
if rg -n 'HNP|home-network|Forgejo|GitHub PR routing|pull-request' roles/common/files/pi/AGENTS.md.d/00-base.md; then
  echo 'FAIL: Pi base fragment contains downstream-specific guidance'
  exit 1
fi
```

Expected: no output and exit status `0`.

- [ ] **Step 4: Verify Ansible syntax**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
ansible-playbook playbook.yml --syntax-check
```

Expected: syntax check succeeds.

- [ ] **Step 5: Commit implementation**

Run:

```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/pi-global-agents-fragments
~/.pi/agent/skills/commit/commit.sh -m "Add Pi global AGENTS fragment assembly" \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/tasks/main.yml
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
