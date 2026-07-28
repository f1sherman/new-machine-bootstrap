# Pi Aube Install Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make provisioning resolve managed Pi from the explicit current Aube-backed mise npm layout for each supported platform.

**Architecture:** Derive one mise install root per task and branch on the Ansible OS family. Darwin uses `bin/pi` and derives the package root from that symlink's real target. Non-Darwin asks Aube for the one installed package at the pinned version, then uses the direct entrypoint and package root under that physical global install. The selected executable and package path are mandatory; no layout probing or fallback is allowed. The non-Darwin `bin/pi` shell shim must not be used as the stable-link target because its relative target breaks when the shim is symlinked outside its own directory. Before managed installation, an idempotent cleanup scans only known npm global-prefix layouts and removes both Pi package identities that can shadow the managed mise npm tool.

**Tech Stack:** Ansible YAML, Bash, Ruby contract tests

## Global Constraints

- Public artifacts must contain no private organization, repository, ticket, employee, development-host, or hosted-workspace references.
- Support one explicit managed layout per platform; do not add heuristic fallback.
- Missing managed executable or package paths remain fatal.
- Preserve replacement of stale managed package symlinks and refusal to overwrite non-symlink destinations.
- Limit cleanup to mise Node, Homebrew, and `/usr/local` global prefixes; never scan the managed mise npm-tool install root.
- Preserve unrelated packages and unrelated `pi` links.

---

### Task 1: Lock and implement the platform-specific Aube paths

**Files:**
- Create: `tests/pi-aube-install-layout-contract.rb`
- Modify: `roles/common/tasks/main.yml:1399-1468`
- Modify: `docs/superpowers/specs/2026-07-27-pi-aube-install-layout-design.md`
- Modify: `docs/superpowers/plans/2026-07-27-pi-aube-install-layout.md`

**Interfaces:**
- Consumes: `mise where npm:@earendil-works/pi-coding-agent`, returning the managed install root, Aube's `list --global --parseable` output from that root, plus `ansible_facts['os_family']`.
- Produces on Darwin: package root derived from `<root>/bin/pi`'s real target and command source `<root>/bin/pi`.
- Produces on non-Darwin: package source `<Aube-listed install>/node_modules/@earendil-works/pi-coding-agent` and command source `<Aube-listed install>/node_modules/@earendil-works/pi-coding-agent/dist/cli.js`.

- [ ] **Step 1: Write the failing platform contract**

Revise the focused contract test to isolate both managed Pi tasks and require:

- an explicit Darwin branch and non-Darwin `else` path in each task;
- both command layouts and rejection of the non-Darwin `bin/pi` shell shim as a stable-link target;
- Darwin package derivation through `Pathname#realpath` on `PI_BIN`;
- non-Darwin resolution of exactly one Aube-listed install at the pinned version and direct package resolution through `Pathname#realpath` on `PI_PACKAGE_ROOT`;
- executable validation before package resolution and command linking;
- package directory validation; and
- the existing stale managed-symlink replacement behavior.

- [ ] **Step 2: Verify RED**

Run: `ruby tests/pi-aube-install-layout-contract.rb`

Expected against the incorrect root-level package implementation: failure reporting that a managed Pi task lacks the required Aube-listed non-Darwin entrypoint.

- [ ] **Step 3: Implement explicit platform paths**

In both managed Pi shell tasks, resolve `pi_root` once and select the executable explicitly:

```bash
if [[ "{{ ansible_facts['os_family'] }}" == "Darwin" ]]; then
  pi_bin="$pi_root/bin/pi"
else
  pi_listing="$(cd "$pi_root" && "$aube_bin" list --global --parseable '@earendil-works/pi-coding-agent')"
  # Require one exact package/version row, then derive pi_install from it.
  pi_bin="$pi_install/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
fi
```

Reject a missing Aube executable, missing or ambiguous package listing, mismatched package name or version, and missing or non-executable `pi_bin` before use.

In the package-link task, export the Aube-listed direct package path only for non-Darwin. Pass the explicit OS family into Ruby. For Darwin, resolve `PI_BIN` and derive the package root from the executable target's parent directories. For non-Darwin, resolve `PI_PACKAGE_ROOT` directly. Require the resulting package root to be a directory before managing the global package link.

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

### Correction: Remove per-Node Pi shadows

**Files:**
- Modify: `tests/purge-legacy-pi-coding-agent.sh`
- Modify: `roles/common/files/bin/purge-legacy-pi-coding-agent`
- Modify: `roles/common/tasks/main.yml`
- Modify: `docs/superpowers/specs/2026-07-27-pi-aube-install-layout-design.md`
- Modify: `docs/superpowers/plans/2026-07-27-pi-aube-install-layout.md`

**Interfaces:**
- Consumes: known npm global-prefix globs, overridable by the behavioral test.
- Produces: removal of `@mariozechner/pi-coding-agent` and `@earendil-works/pi-coding-agent` package directories plus only their matching `bin/pi` links; prints `changed` or `unchanged`.

- [ ] **Step 1: Strengthen the behavioral cleanup test**

Create both stale package identities in isolated scanned prefixes. Also create unrelated same-scope packages, an unrelated `pi` link, and a managed mise npm-tool install root outside the scanned prefix override. Require both stale packages and matching links to be removed, empty scope directories to be removed, unrelated and managed content to survive, and a second run to report `unchanged`.

- [ ] **Step 2: Verify RED**

Run: `bash tests/purge-legacy-pi-coding-agent.sh`

Expected against the single-package cleanup: failures for the remaining `@earendil-works/pi-coding-agent` directory, scope, and matching `pi` link.

- [ ] **Step 3: Purge both stale package identities**

Iterate over the two fixed Pi package identities within each scanned prefix. Remove each package directory, remove its scope directory only when empty, and remove `bin/pi` only when `readlink` points into either identity. Keep the existing Bash 3.2-compatible prefix-glob override and changed/unchanged output.

Update the Ansible task name and comments to describe managed npm-tool shadow cleanup rather than rename-only cleanup.

- [ ] **Step 4: Verify behavior and contracts**

Run:

```bash
bash tests/purge-legacy-pi-coding-agent.sh
bash -n roles/common/files/bin/purge-legacy-pi-coding-agent
ruby tests/pi-aube-install-layout-contract.rb
ruby tests/pi-managed-aube-update-contract.rb
ruby -e 'require "yaml"; YAML.load_file("roles/common/tasks/main.yml"); puts "YAML valid"'
git diff --check
```

Expected: all commands exit 0.

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

Expected: on Darwin the link target ends in `/bin/pi`; on non-Darwin it runs the direct `/global-aube/.../node_modules/@earendil-works/pi-coding-agent/dist/cli.js` entrypoint. Pi reports the managed version.

- [ ] **Step 3: Re-run focused validation**

Run:

```bash
ruby tests/pi-aube-install-layout-contract.rb
ruby tests/pi-managed-aube-update-contract.rb
```

Expected: both pass.
