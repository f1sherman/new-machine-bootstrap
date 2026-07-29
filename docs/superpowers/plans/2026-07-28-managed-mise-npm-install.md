# Managed mise npm Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the managed npm-tool provisioning task install only Codex and Pi, and resolve Linux Pi from its deterministic mise npm tree.

**Architecture:** Keep installation ownership in the existing Ansible role. Replace the home-wide mise install with explicit npm tool selectors, then derive and validate the Linux package directly under the mise tool root rather than querying Aube global state.

**Tech Stack:** Ansible YAML, Bash, Ruby contract tests, mise, Aube.

## Global Constraints

- Public repository content must not mention internal companies, repositories, ticket identifiers, or internal remote-environment conventions.
- Preserve existing Aube paranoid and release-age environment policy.
- Preserve the existing macOS Pi path and stale managed-symlink replacement behavior.
- Do not add compatibility probing for historical package layouts.
- Use TDD: observe each changed contract test fail for the intended reason before production edits.

---

### Task 1: Target only managed npm tools

**Files:**
- Create: `tests/managed-mise-npm-install-contract.rb`
- Modify: `roles/common/tasks/main.yml:1275-1291`

**Interfaces:**
- Consumes: `tool_versions.runtimes.pi_coding_agent` and the existing mise/Aube environment.
- Produces: an Ansible command that installs `npm:@openai/codex@latest` and `npm:@earendil-works/pi-coding-agent@<pinned version>` only.

- [ ] **Step 1: Write the failing contract test**

Create a Ruby test that extracts the task beginning `- name: Install managed mise npm tools through aube` and ending at the next task. Embed that task in a temporary playbook, execute it through Ansible with a recording mise fixture, and require the exact rendered arguments:

```ruby
[
  "install",
  "--yes",
  "npm:@openai/codex@latest",
  "npm:@earendil-works/pi-coding-agent@9.8.7"
]
```

Also require the executed task to pass Aube paranoid mode, the Aube package-manager selection, and the Codex release-age exemption.

- [ ] **Step 2: Run the test and verify RED**

Run: `ruby tests/managed-mise-npm-install-contract.rb`

Expected: FAIL because the task still contains the home-wide install and lacks explicit selectors.

- [ ] **Step 3: Implement the targeted command**

Change only the command to the equivalent of:

```yaml
command: >-
  {{ mise_bin }} install --yes
  'npm:@openai/codex@latest'
  'npm:@earendil-works/pi-coding-agent@{{ tool_versions.runtimes.pi_coding_agent }}'
```

Keep retries and environment unchanged.

- [ ] **Step 4: Verify GREEN and adjacent policy**

Run:

```bash
ruby tests/managed-mise-npm-install-contract.rb
ruby tests/paranoid-package-tools.rb
ruby tests/pi-managed-aube-update-contract.rb
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add tests/managed-mise-npm-install-contract.rb roles/common/tasks/main.yml
git commit -m "Target managed npm tool installation"
```

### Task 2: Resolve Linux Pi beneath the mise tool root

**Files:**
- Modify: `tests/pi-aube-install-layout-contract.rb`
- Modify: `roles/common/tasks/main.yml:1399-1478`

**Interfaces:**
- Consumes: `pi_root` from `mise where npm:@earendil-works/pi-coding-agent`.
- Produces: `PI_PACKAGE_ROOT=$pi_root/node_modules/@earendil-works/pi-coding-agent` and `PI_BIN=$PI_PACKAGE_ROOT/dist/cli.js` after manifest validation.

- [ ] **Step 1: Rewrite the Linux layout contract to describe the observed tree**

Remove expectations for `aube list --global`, tab-separated listing parsing, and `pi_install`. Require both managed Pi tasks to derive:

```bash
pi_package_root="$pi_root/node_modules/@earendil-works/pi-coding-agent"
pi_manifest="$pi_package_root/package.json"
pi_name="$(jq -er '.name | select(type == "string")' "$pi_manifest")"
pi_version="$(jq -er '.version | select(type == "string")' "$pi_manifest")"
```

Require exact name/version validation and `dist/cli.js`. In the executable fixture, create a wrapper root `package.json`, the nested package manifest, and nested executable; execute the extracted non-Darwin resolver and assert the nested paths are returned. Also assert the resolver does not contain `list --global`.

- [ ] **Step 2: Run the test and verify RED**

Run: `ruby tests/pi-aube-install-layout-contract.rb`

Expected: FAIL because production still queries Aube global state.

- [ ] **Step 3: Implement deterministic package resolution**

In both non-Darwin branches, replace Aube listing logic with direct nested path derivation. Validate the nested `package.json` name and pinned version with `jq -er`, then use `dist/cli.js`. Export `PI_PACKAGE_ROOT` in the package-link task. Preserve the Darwin branch and Ruby symlink logic unchanged.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
ruby tests/pi-aube-install-layout-contract.rb
ruby tests/managed-mise-npm-install-contract.rb
ruby tests/pi-managed-aube-update-contract.rb
ruby tests/paranoid-package-tools.rb
```

Expected: all pass.

- [ ] **Step 5: Run repository checks and provision**

Run the repository's focused test suite for changed contracts, `git diff --check`, then run `bin/provision` from this worktree. Confirm exit 0 and inspect the current `/tmp/provision-*.log` provenance and recap.

- [ ] **Step 6: Commit**

```bash
git add tests/pi-aube-install-layout-contract.rb roles/common/tasks/main.yml
git commit -m "Resolve managed Pi from its mise install root"
```
