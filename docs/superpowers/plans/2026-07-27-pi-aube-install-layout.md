# Pi Aube Install Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make provisioning resolve managed Pi from the explicit current Aube-backed mise npm layout for each supported platform.

**Architecture:** Derive one mise install root per task and branch on the Ansible OS family. Darwin uses `bin/pi` and derives the package root from that symlink's real target. Non-Darwin uses the direct package entrypoint `node_modules/@earendil-works/pi-coding-agent/dist/cli.js` and the direct `node_modules/@earendil-works/pi-coding-agent` package root. The selected executable and package path are mandatory; no layout probing or fallback is allowed. The non-Darwin `node_modules/.bin/pi` shell shim must not be used as the stable-link target because its relative target breaks when the shim is symlinked outside its own directory.

**Tech Stack:** Ansible YAML, Bash, Ruby contract tests

## Global Constraints

- Public artifacts must contain no private organization, repository, ticket, employee, development-host, or hosted-workspace references.
- Support one explicit managed layout per platform; do not add heuristic fallback.
- Missing managed executable or package paths remain fatal.
- Preserve replacement of stale managed package symlinks and refusal to overwrite non-symlink destinations.

---

### Task 1: Lock and implement the platform-specific Aube paths

**Files:**
- Create: `tests/pi-aube-install-layout-contract.rb`
- Modify: `roles/common/tasks/main.yml:1399-1468`
- Modify: `docs/superpowers/specs/2026-07-27-pi-aube-install-layout-design.md`
- Modify: `docs/superpowers/plans/2026-07-27-pi-aube-install-layout.md`

**Interfaces:**
- Consumes: `mise where npm:@earendil-works/pi-coding-agent`, returning the managed install root, plus `ansible_facts['os_family']`.
- Produces on Darwin: package root derived from `<root>/bin/pi`'s real target and command source `<root>/bin/pi`.
- Produces on non-Darwin: package source `<root>/node_modules/@earendil-works/pi-coding-agent` and command source `<root>/node_modules/@earendil-works/pi-coding-agent/dist/cli.js`.

- [ ] **Step 1: Write the failing platform contract**

Revise the focused contract test to isolate both managed Pi tasks and require:

- an explicit Darwin branch and non-Darwin `else` path in each task;
- both command layouts and rejection of the non-Darwin `node_modules/.bin/pi` shell shim as a stable-link target;
- Darwin package derivation through `Pathname#realpath` on `PI_BIN`;
- non-Darwin direct package resolution through `Pathname#realpath` on `PI_PACKAGE_ROOT`;
- executable validation before package resolution and command linking;
- package directory validation; and
- the existing stale managed-symlink replacement behavior.

- [ ] **Step 2: Verify RED**

Run: `ruby tests/pi-aube-install-layout-contract.rb`

Expected against the shim-target implementation: failure reporting that a managed Pi task lacks the required direct non-Darwin entrypoint or still selects the relocatable shell shim.

- [ ] **Step 3: Implement explicit platform paths**

In both managed Pi shell tasks, resolve `pi_root` once and select the executable explicitly:

```bash
if [[ "{{ ansible_facts['os_family'] }}" == "Darwin" ]]; then
  pi_bin="$pi_root/bin/pi"
else
  pi_bin="$pi_root/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
fi
```

Reject a missing or non-executable `pi_bin` before using it.

In the package-link task, export the direct package path only for non-Darwin. Pass the explicit OS family into Ruby. For Darwin, resolve `PI_BIN` and derive the package root from the executable target's parent directories. For non-Darwin, resolve `PI_PACKAGE_ROOT` directly. Require the resulting package root to be a directory before managing the global package link.

Do not alter stale managed-link replacement.

- [ ] **Step 4: Verify GREEN and syntax**

Run:

```bash
ruby tests/pi-aube-install-layout-contract.rb
ruby -e 'require "yaml"; YAML.load_file("roles/common/tasks/main.yml"); puts "YAML valid"'
ruby tests/pi-managed-aube-update-contract.rb
git diff --check
git diff --check HEAD -- roles/common/tasks/main.yml tests/pi-aube-install-layout-contract.rb docs/superpowers/specs/2026-07-27-pi-aube-install-layout-design.md docs/superpowers/plans/2026-07-27-pi-aube-install-layout.md
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit correction**

Commit the contract, implementation, approved documents, and Task 1 fix-round evidence without AI attribution.

### Task 2: Verify provisioning behavior

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the corrected platform-specific Ansible tasks.
- Produces: a valid `~/.local/bin/pi` and active package link after provisioning.

- [ ] **Step 1: Run repository verification**

Run: `bin/provision`

Expected: exit 0 with a new provision log whose provenance identifies this worktree and correction commit.

- [ ] **Step 2: Verify installed command**

Run:

```bash
test -x ~/.local/bin/pi
readlink ~/.local/bin/pi
pi --version
```

Expected: on Darwin the link target ends in `/bin/pi`; on non-Darwin it ends in `/node_modules/@earendil-works/pi-coding-agent/dist/cli.js`. Pi reports the managed version.

- [ ] **Step 3: Re-run focused validation**

Run:

```bash
ruby tests/pi-aube-install-layout-contract.rb
ruby tests/pi-managed-aube-update-contract.rb
```

Expected: both pass.
