# Pi Async Runtime Dependencies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision the Pi companion packages required by detached async subagents.

**Architecture:** Extend the existing common-role Pi installation sequence. Aube adds exact-version server and client packages to mise's generated Pi wrapper project, then Node imports the exports required by pi-subagents.

**Tech Stack:** Ansible, Bash, mise, Aube, Node.js

**Spec:** `docs/superpowers/specs/2026-09-17-pi-async-runtime-dependencies-design.md`

## Global Constraints

- Use `tool_versions.runtimes.pi_coding_agent` for both companion package versions.
- Keep all deployed-state changes in Ansible.
- Do not patch Pi or pi-subagents source.
- Verify a real detached async child after provisioning.

---

### Task 1: Provision and verify Pi async runtime packages

**Files:**
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: the existing mise Pi wrapper from `mise where npm:@earendil-works/pi-coding-agent` and `tool_versions.runtimes.pi_coding_agent`.
- Produces: resolvable `@earendil-works/pi-server`, `@earendil-works/pi-server/unix`, and `@earendil-works/pi-client/unix` exports in the Pi wrapper dependency tree.

- [ ] **Step 1: Record the failing runtime proof**

Run from the installed Pi wrapper before implementation:

```bash
pi_root="$(mise where 'npm:@earendil-works/pi-coding-agent')"
cd "$pi_root"
node --input-type=module --eval \
  'await import("@earendil-works/pi-server");
   await import("@earendil-works/pi-server/unix");
   await import("@earendil-works/pi-client/unix");'
```

Expected: FAIL with `ERR_MODULE_NOT_FOUND` for a missing companion package.

- [ ] **Step 2: Add the provisioning task**

Insert this task after `Repair broken managed Pi installation` and before Pi plugin installation:

```yaml
- name: Install Pi async runtime dependencies
  shell: |
    set -euo pipefail
    pi_root="$("{{ mise_bin }}" where 'npm:@earendil-works/pi-coding-agent')"
    "{{ mise_bin }}" exec aube@{{ tool_versions.runtimes.aube }} -- \
      aube --dir "$pi_root" add --save-exact --allow-low-downloads \
      --ignore-workspace-root-check \
      --deny-build=@google/genai --deny-build=esbuild \
      --deny-build=protobufjs \
      '@earendil-works/pi-server@{{ tool_versions.runtimes.pi_coding_agent }}' \
      '@earendil-works/pi-client@{{ tool_versions.runtimes.pi_coding_agent }}'
    cd "$pi_root"
    "{{ mise_bin }}" exec node@{{ tool_versions.runtimes.node }} -- \
      node --input-type=module --eval \
      'await import("@earendil-works/pi-server");
       await import("@earendil-works/pi-server/unix");
       await import("@earendil-works/pi-client/unix");'
  args:
    executable: /bin/bash
  environment:
    AUBE_PARANOID: "true"
    PATH: "{{ ansible_facts['user_dir'] }}/.local/bin:{{ ansible_facts['env']['PATH'] }}"
  changed_when: false
```

- [ ] **Step 3: Run static validation**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file("roles/common/tasks/main.yml")'
ansible-playbook playbook.yml --syntax-check
```

Expected: both commands exit 0.

- [ ] **Step 4: Provision the implementation**

Run:

```bash
bin/provision
```

Expected: provisioning exits 0 and the Pi async runtime dependency task passes.

- [ ] **Step 5: Verify installed package exports**

Run:

```bash
pi_root="$(mise where 'npm:@earendil-works/pi-coding-agent')"
cd "$pi_root"
node --input-type=module --eval \
  'await import("@earendil-works/pi-server");
   await import("@earendil-works/pi-server/unix");
   await import("@earendil-works/pi-client/unix");'
```

Expected: exit 0 with no output.

- [ ] **Step 6: Verify a detached child end to end**

Start one async `delegate` subagent that returns a fixed short response. Wait for its completion through the registered subagent interface.

Expected: the child reaches `completed` without a missing-package diagnostic.

- [ ] **Step 7: Verify convergence and the diff**

Run:

```bash
bin/provision --check
git diff --check
```

Expected: both commands exit 0.

- [ ] **Step 8: Commit**

```bash
git add roles/common/tasks/main.yml \
  docs/superpowers/plans/2026-09-17-pi-async-runtime-dependencies.md
git commit -m "Fix Pi async runtime dependencies"
```
