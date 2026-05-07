# Heal mise node installs with broken symlinks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure every mise-managed node install on the machine has working `node`, `npm`, and `npx` binaries after `bin/provision`, fixing broken-symlink partial installs that PR #155 missed, on both macOS and Linux dev hosts.

**Architecture:** Extract a shared Ansible task file `roles/common/tasks/heal_mise_node_installs.yml` that enumerates every mise-installed node version, exec-tests `node --version`, `npm --version`, `npx --version` on each, and `mise install --force`s any version where any binary fails. macOS calls wrap the force-install in a temporary `GNUPGHOME` to preserve PR #110's keyring isolation. Both `roles/macos/tasks/main.yml` and the Linux branch of `roles/common/tasks/main.yml` `include_tasks` the new file before their existing pinned-version-install logic.

**Tech Stack:** Ansible (YAML, Jinja2 expressions, `shell` / `command` / `tempfile` / `file` modules), `mise` CLI, zsh on macOS / bash on Linux dev hosts.

**Spec:** `docs/superpowers/specs/2026-05-06-mise-node-broken-symlink-heal-design.md`

---

## File Structure

- **Create**: `roles/common/tasks/heal_mise_node_installs.yml` — single-purpose: heal any broken mise-installed node version. Owns: enumerating installed versions, exec-based health check, GPG-isolated force reinstall on macOS, plain force reinstall on Linux. ~50 lines.
- **Modify**: `roles/macos/tasks/main.yml` lines 72-115 — replace the per-version stat check + force-install block (which only covers the pinned version) with an `include_tasks` of the new heal file, then keep a simplified "install pinned if not listed" block that retains its own GPG-home wrapper for the first-install case.
- **Modify**: `roles/common/tasks/main.yml` lines 527-543 (Linux node section) — `include_tasks` the new heal file before the existing "check / install pinned / set global" steps. The existing steps stay; they handle the case where the pinned version isn't installed at all.

The new file is included via `include_tasks` (matching the existing `resolve_mise_binary.yml` precedent at `roles/macos/tasks/main.yml:42` and `roles/common/tasks/main.yml:510`).

## Notes for the implementer

- **Ansible idioms.** `shell` runs through a shell (use for pipes, awk, redirection); `command` runs the binary directly (use when arguments are literal). `register` captures the result. `failed_when: false` and `changed_when: false` are needed on health-check tasks because they intentionally probe for failure and shouldn't change facts/idempotency reporting.
- **Looping.** `loop:` iterates a list. To iterate a Cartesian product (e.g. each version × each binary), use a Jinja2 expression: `loop: "{{ versions | product(['node','npm','npx']) | list }}"`. The loop var becomes a 2-tuple; access with `item.0` and `item.1`.
- **Block / always.** `block:` groups tasks; `always:` inside the same block runs whether or not the block's tasks succeeded. We use this so the temp GPG home gets cleaned up even if reinstall fails. If the block's `when` evaluates false, the block does not run *and* the always is skipped — that's fine, because the temp dir was never created.
- **`mise ls node` output.** Each line looks like `node  20.11.0  ~/.config/mise/config.toml ...` or similar. The version is the second whitespace-separated column when the first column is `node`. The existing `awk '$1 == "node" { print $2 }'` pattern in `roles/common/tasks/main.yml:528` is the established style — use it.
- **GPG home isolation rationale.** `mise install` on macOS runs `gpg --verify` against the user's gnupg keyring, which can fail when the keyring is locked or has unrelated trust state. PR #110 solved this by pointing `GNUPGHOME` at a fresh temp dir for the duration of the install. The same workaround is applied here.
- **Variable scope.** Variables registered inside an `include_tasks`'d file are visible in the including file. We rely on this — the heal file registers `mise_node_broken_versions` only inside its own scope; the including file does not need to read it.
- **Always start with a worktree branch on this repo.** A `block-main-branch-edits` hook will reject edits on `main`. The branch `mise-node-broken-symlink-heal` was created via `repo-start` for this work — verify with `git status -sb` before editing.
- **Commits.** Use the `_commit` skill for every commit step. The repo blocks direct `git commit` invocations.

---

## Task 1: Create the shared heal task file

**Files:**
- Create: `roles/common/tasks/heal_mise_node_installs.yml`

- [ ] **Step 1: Verify you're on the feature branch**

Run: `git status -sb`
Expected output (or similar):
```
## mise-node-broken-symlink-heal
```
If output shows `## main`, stop and run `~/.local/bin/repo-start mise-node-broken-symlink-heal --print-path` then `cd` into the printed path.

- [ ] **Step 2: Create the heal task file**

Create `roles/common/tasks/heal_mise_node_installs.yml` with this exact content:

```yaml
---
# Auto-heal mise-managed Node.js installs.
#
# Some Node tarballs ship a bin/npx that is a symlink to
# lib/node_modules/npm/bin/npx-cli.js — but the target file is missing,
# leaving a dangling symlink. The previous heal logic used Ansible's stat
# module with default follow:false, so a broken symlink reported
# stat.exists:true and the version looked healthy.
#
# Strategy: enumerate every mise-installed node version, exec --version on
# node/npm/npx, and force-reinstall any version where any of those exec'd
# binaries returns non-zero.

- name: Enumerate installed mise node versions
  shell: "{{ mise_bin }} ls node | awk '$1 == \"node\" { print $2 }'"
  register: mise_node_installed_versions
  changed_when: false

- name: Health-check each installed mise node version
  shell: "{{ ansible_facts['user_dir'] }}/.local/share/mise/installs/node/{{ item.0 }}/bin/{{ item.1 }} --version"
  loop: "{{ mise_node_installed_versions.stdout_lines | product(['node', 'npm', 'npx']) | list }}"
  register: mise_node_healthcheck
  changed_when: false
  failed_when: false

- name: Compute set of broken mise node versions
  set_fact:
    mise_node_broken_versions: >-
      {{
        mise_node_healthcheck.results
        | selectattr('rc', 'ne', 0)
        | map(attribute='item')
        | map('first')
        | unique
        | list
      }}

- name: Reinstall broken mise node versions
  block:
    - name: Create temporary GPG home for mise node reinstall (macOS)
      tempfile:
        state: directory
        prefix: mise-node-heal-gpg-
      register: mise_node_heal_gpg_home
      when: ansible_facts['os_family'] == 'Darwin'

    - name: Force-reinstall broken mise node versions
      command: "{{ mise_bin }} install --force node@{{ item }}"
      loop: "{{ mise_node_broken_versions }}"
      environment: "{{ {'GNUPGHOME': mise_node_heal_gpg_home.path} if (ansible_facts['os_family'] == 'Darwin' and mise_node_heal_gpg_home is defined and mise_node_heal_gpg_home.path is defined) else {} }}"
  always:
    - name: Remove temporary GPG home for mise node reinstall (macOS)
      file:
        path: "{{ mise_node_heal_gpg_home.path }}"
        state: absent
      when:
        - ansible_facts['os_family'] == 'Darwin'
        - mise_node_heal_gpg_home is defined
        - mise_node_heal_gpg_home.path is defined
  when: mise_node_broken_versions | length > 0
```

- [ ] **Step 3: Lint the YAML for syntax**

Run: `python3 -c 'import yaml; yaml.safe_load(open("roles/common/tasks/heal_mise_node_installs.yml"))'`
Expected: exits 0 with no output.

- [ ] **Step 4: Commit the new file**

Use the `_commit` skill (the repo blocks direct `git commit`). Provide this summary to the committer:

> Add a shared task file that enumerates every mise-installed node version, exec-tests node/npm/npx, and force-reinstalls any broken version. Wraps the macOS reinstall in a temporary GNUPGHOME (mirroring PR #110). Not yet wired into either platform's main.yml — wiring happens in subsequent tasks.

Files: `roles/common/tasks/heal_mise_node_installs.yml`.

---

## Task 2: Wire heal file into the macOS playbook

**Files:**
- Modify: `roles/macos/tasks/main.yml:72-115`

- [ ] **Step 1: Read the existing block to confirm line numbers**

Run: `awk 'NR>=72 && NR<=115' roles/macos/tasks/main.yml`
Expected: starts with the `Check if pinned Node.js version is listed by mise` task and ends with the `Remove temporary GPG home for macOS Node.js install` task. If line numbers have drifted, re-locate the equivalent block before editing.

- [ ] **Step 2: Replace the block with an include + simplified pinned-install**

Replace the block from "Check if pinned Node.js version is listed by mise" through "Remove temporary GPG home for macOS Node.js install" (current lines 72-115) with this exact YAML:

```yaml
- name: Heal any broken mise-managed Node.js installs (macOS)
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/heal_mise_node_installs.yml'

- name: Check if pinned Node.js version is listed by mise (macOS)
  shell: "{{ mise_bin }} ls node | awk '$1 == \"node\" && $2 == \"{{ tool_versions.runtimes.node }}\" { found = 1 } END { exit(found ? 0 : 1) }'"
  register: macos_node_listed
  changed_when: false
  failed_when: false

- name: Create temporary GPG home for first-install of pinned Node.js (macOS)
  tempfile:
    state: directory
    prefix: macos-node-pin-gpg-
  register: macos_node_pin_gpg_home
  when: macos_node_listed.rc != 0

- name: Install pinned Node.js version if not listed (macOS)
  command: "{{ mise_bin }} install node@{{ tool_versions.runtimes.node }}"
  environment:
    GNUPGHOME: "{{ macos_node_pin_gpg_home.path }}"
  when:
    - macos_node_listed.rc != 0
    - macos_node_pin_gpg_home.path is defined

- name: Remove temporary GPG home for first-install of pinned Node.js (macOS)
  file:
    path: "{{ macos_node_pin_gpg_home.path }}"
    state: absent
  when:
    - macos_node_listed.rc != 0
    - macos_node_pin_gpg_home.path is defined
```

The next task in the file ("Get current global Node.js version from mise config") is unchanged.

- [ ] **Step 3: Lint the YAML**

Run: `python3 -c 'import yaml; yaml.safe_load(open("roles/macos/tasks/main.yml"))'`
Expected: exits 0 with no output.

- [ ] **Step 4: Sanity-check via Ansible syntax check**

Run: `ansible-playbook playbook.yml --syntax-check`
Expected: prints `playbook: playbook.yml` and exits 0.

- [ ] **Step 5: Commit**

Use the `_commit` skill. Summary:

> Wire the new heal task file into the macOS playbook, replacing the previous stat-based per-binary check that missed dangling symlinks. Keep a separate GPG-isolated install for the case where the pinned version is not yet installed at all (first-install path).

Files: `roles/macos/tasks/main.yml`.

---

## Task 3: Wire heal file into the Linux branch

**Files:**
- Modify: `roles/common/tasks/main.yml:527-543`

- [ ] **Step 1: Read the existing block to confirm line numbers**

Run: `awk 'NR>=527 && NR<=543' roles/common/tasks/main.yml`
Expected: starts with `Check if pinned Node.js version is installed (Linux)` and ends with `Set global Node.js version via mise (Linux)`. If line numbers have drifted, re-locate the equivalent block before editing.

- [ ] **Step 2: Insert the heal include before the existing Linux node block**

Insert this block immediately *before* the `Check if pinned Node.js version is installed (Linux)` task (current line 527):

```yaml
- name: Heal any broken mise-managed Node.js installs (Linux)
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/heal_mise_node_installs.yml'
  when: ansible_facts["os_family"] == "Debian"

```

Leave the existing Linux node tasks (`Check if pinned Node.js version is installed (Linux)`, `Install pinned Node.js version if not installed (Linux)`, `Set global Node.js version via mise (Linux)`) unchanged.

- [ ] **Step 3: Lint the YAML**

Run: `python3 -c 'import yaml; yaml.safe_load(open("roles/common/tasks/main.yml"))'`
Expected: exits 0 with no output.

- [ ] **Step 4: Sanity-check via Ansible syntax check**

Run: `ansible-playbook playbook.yml --syntax-check`
Expected: prints `playbook: playbook.yml` and exits 0.

- [ ] **Step 5: Commit**

Use the `_commit` skill. Summary:

> Wire the new heal task file into the Linux dev host branch. The existing 'install pinned if not listed' and 'set global' steps are unchanged — they handle the case where the pinned version is not installed at all.

Files: `roles/common/tasks/main.yml`.

---

## Task 4: Verify on the affected machine

**Files:** none (verification only).

- [ ] **Step 1: Confirm the broken install still exists pre-provision**

Run: `ls -la ~/.local/share/mise/installs/node/22.21.1/bin/npx`
Expected: shows a symlink to `../lib/node_modules/npm/bin/npx-cli.js`. (If 22.21.1 is no longer present, find any installed version where `~/.local/share/mise/installs/node/<v>/bin/npx --version` fails. If none are broken, skip to Step 4 — the heal path is exercised in Step 2 of Task 1's lint and Task 2/3's syntax checks but cannot be empirically verified against a known-broken version on this machine.)

- [ ] **Step 2: Confirm the broken binary fails in isolation**

Run: `~/.local/share/mise/installs/node/22.21.1/bin/npx --version 2>&1 | head -5`
Expected: error mentioning "no such file or directory" or similar — confirming the version is broken before provision.

- [ ] **Step 3: Run provision**

Run: `bin/provision`
Expected: completes without error. The `Compute set of broken mise node versions` task should report a non-empty list (visible in `-v` output if needed) and the `Force-reinstall broken mise node versions` task should run and succeed.

- [ ] **Step 4: Confirm the previously-broken install is now healthy**

Run: `~/.local/share/mise/installs/node/22.21.1/bin/npx --version`
Expected: prints a version number, exits 0.

Run: `~/.local/share/mise/installs/node/22.21.1/bin/npm --version`
Expected: prints a version number, exits 0.

- [ ] **Step 5: Confirm idempotency**

Run: `bin/provision`
Expected: completes without error. The `Compute set of broken mise node versions` step should produce an empty list, and the `Reinstall broken mise node versions` block should be skipped.

- [ ] **Step 6: Confirm temp GPG dirs were not leaked**

Run: `ls -d /var/folders/*/T/mise-node-heal-gpg-* 2>/dev/null; ls -d /var/folders/*/T/macos-node-pin-gpg-* 2>/dev/null`
Expected: empty output (no matching directories). On Linux, run: `ls -d /tmp/mise-node-heal-gpg-* 2>/dev/null` — same expectation.

- [ ] **Step 7: Spot-check that the original failure mode is fixed**

If the affected mac has a repo with a `mise.toml` pinning the previously-broken node version, open Claude Code in that repo and run `claude mcp list` (or `/mcp`). The `slack` MCP server (or any other npx-spawned server) should now show as connected, not `✗ failed`. Restart Claude Code if it had captured a stale PATH state. (Skip this step if no such repo exists on the machine.)

---

## Self-Review Checklist

Run this checklist mentally after writing the plan, against the spec at `docs/superpowers/specs/2026-05-06-mise-node-broken-symlink-heal-design.md`.

- ✅ **Spec coverage — health check is exec-based, not stat-based.** Task 1 step 2: `Health-check each installed mise node version` task uses `shell` to exec `bin/<binary> --version` and captures `rc` via `failed_when: false` + `register`.
- ✅ **Spec coverage — applies to every installed version.** Task 1 step 2: `Enumerate installed mise node versions` lists every entry from `mise ls node` and the next task loops over the product with `[node, npm, npx]`.
- ✅ **Spec coverage — heal applies to both platforms.** Task 2 wires it into macOS; Task 3 wires it into Linux with the `os_family == 'Debian'` guard.
- ✅ **Spec coverage — macOS GPG isolation preserved.** Task 1 step 2 includes the GPG home setup inside the heal file's `block`/`always`. Task 2 keeps a separate GPG home for the pinned-version first-install case.
- ✅ **Spec coverage — temp GPG home torn down even on failure.** `block`/`always` structure in Task 1 step 2 ensures cleanup.
- ✅ **Spec coverage — empty mise ls node ⇒ no-op.** When `mise_node_installed_versions.stdout_lines` is empty, the product loop is empty, `mise_node_broken_versions` becomes `[]`, and the reinstall block is skipped via `when: mise_node_broken_versions | length > 0`.
- ✅ **Spec coverage — broken pinned version case.** If the pinned version is listed but broken, heal file reinstalls it; Task 2's "install if not listed" step then sees it listed and skips.
- ✅ **Spec coverage — testing.** Task 4 covers manual repro, idempotency, and CI no-op (CI is exercised implicitly by syntax checks in tasks 1-3 and the existing integration-test workflow).
- ✅ **No placeholders.** Every code block is concrete; no TBD/TODO.
- ✅ **Type/method consistency.** `mise_node_broken_versions` is set in Task 1 step 2's `set_fact` task and read in the same task file's `when` clauses. Variable name matches in all references.
