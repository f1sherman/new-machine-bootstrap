# Auto-trust mise configs under `~/projects` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an idempotent Ansible task pair that registers `$HOME/projects` in mise's `trusted_config_paths`, so any mise config under `~/projects` is auto-trusted on macOS and Linux dev hosts.

**Architecture:** A single edit to `roles/common/tasks/main.yml` inserts two YAML tasks immediately before the existing `Trust mise config (Linux)` task. The first task captures the current `trusted_config_paths` value with `mise settings get`; the second task calls `mise settings add` only when the user's projects path (wrapped in literal quotes for exact-match safety) is absent from that captured value. The tasks run on every platform — Codespaces gets a harmless no-op because `~/projects` doesn't exist there.

**Tech Stack:** Ansible (`command` module, Jinja2 conditionals), `mise` CLI (`settings get`, `settings add`, `settings unset`), `bin/provision` wrapper.

**Spec:** `docs/superpowers/specs/2026-04-07-auto-trust-mise-projects-design.md`

---

## File Structure

- **Modify:** `roles/common/tasks/main.yml` — insert two new tasks immediately before line 312 (`- name: Trust mise config (Linux)`).

No new files. No test files (Ansible's testing surface for this change is the `bin/provision` run itself plus direct `mise settings get` queries).

---

## Task 1: Add the auto-trust task pair

**Files:**
- Modify: `roles/common/tasks/main.yml` (insert two tasks just above line 312)

### Steps

- [ ] **Step 1: Establish the Red baseline**

Reset `trusted_config_paths` to empty so we can prove the task actually changes state:

```bash
mise settings unset trusted_config_paths
mise settings get trusted_config_paths
```

Expected output of the second command:
```
[]
```

If the unset command errors with "setting not found" or similar, that's also acceptable — it means the setting is already empty. The `get` output is the source of truth.

- [ ] **Step 2: Confirm Red — provision does nothing for trust paths yet**

Run a dry-run of provision and confirm there is no existing task that touches `trusted_config_paths`:

```bash
bin/provision --check 2>&1 | grep -i "trusted_config_paths" || echo "no existing task — Red confirmed"
```

Expected output:
```
no existing task — Red confirmed
```

If grep finds a hit, stop and investigate — someone may have already added a similar task.

- [ ] **Step 3: Read the surrounding context in main.yml**

Open `roles/common/tasks/main.yml` and locate the `Trust mise config (Linux)` task at line 312. The new tasks will be inserted immediately above it. Confirm the surrounding context matches:

```yaml
- name: Install ccstatusline widget configuration
  copy:
    src: '{{ playbook_dir }}/roles/common/files/config/ccstatusline/settings.json'
    dest: '{{ ansible_facts["user_dir"] }}/.config/ccstatusline/settings.json'
    mode: '0600'

- name: Trust mise config (Linux)
  command: "mise trust {{ playbook_dir }}/mise.toml"
  changed_when: false
  when: ansible_facts["os_family"] == "Debian"
```

If the file has drifted from this layout, adjust the insertion point accordingly — the new tasks must sit between `Install ccstatusline widget configuration` and `Trust mise config (Linux)`.

- [ ] **Step 4: Insert the two new tasks**

Insert the following YAML block in `roles/common/tasks/main.yml`, immediately before the `- name: Trust mise config (Linux)` task. There must be exactly one blank line between the new block and the existing `Trust mise config (Linux)` task, matching the file's existing spacing convention.

```yaml
- name: Get current mise trusted_config_paths
  command: mise settings get trusted_config_paths
  register: mise_trusted_paths
  changed_when: false

- name: Auto-trust mise configs under ~/projects
  command: mise settings add trusted_config_paths "{{ ansible_facts['user_dir'] }}/projects"
  when: ('"' + ansible_facts['user_dir'] + '/projects"') not in mise_trusted_paths.stdout
```

Notes for the implementing agent:
- The `when` condition uses single-quoted Jinja with embedded literal `"` characters. Do not change the quoting style.
- The `Get current` task has `changed_when: false` because reading state should never report `changed`.
- The `Auto-trust` task has no `changed_when` override — Ansible will report `changed` when it runs and `skipping` when the `when` guard is false. That is the desired behavior.

- [ ] **Step 5: Run the playbook**

```bash
bin/provision
```

Expected: the playbook runs to completion. The `Get current mise trusted_config_paths` task reports `ok`. The `Auto-trust mise configs under ~/projects` task reports `changed` (because we reset state in Step 1).

If `bin/provision` fails with a YAML parsing error, the indentation is wrong — fix and re-run.

- [ ] **Step 6: Verify Green — the setting is now populated**

```bash
mise settings get trusted_config_paths
```

Expected output (substituting your actual home directory):
```
["/Users/brian/projects"]
```

If the output is still `[]`, the task did not run. Re-check the `when` condition and the YAML indentation.

- [ ] **Step 7: Verify idempotency — second run skips the add task**

```bash
bin/provision 2>&1 | grep -A 1 "Auto-trust mise configs under ~/projects"
```

Expected output:
```
TASK [common : Auto-trust mise configs under ~/projects] ***
skipping: [localhost]
```

If the second run reports `changed` instead of `skipping`, the `when` guard is broken — most likely the substring check is matching the wrong format. Inspect `mise settings get trusted_config_paths` output and adjust the condition.

- [ ] **Step 8: Functional verification — a config under ~/projects is auto-trusted**

Pick a real mise config under `~/projects` and confirm mise treats it as trusted via the prefix rule. The bootstrap repo's own `mise.toml` is a convenient target:

```bash
cd "$HOME/projects/new-machine-bootstrap" && mise trust --show
```

Expected: every line of output containing a path under `$HOME/projects/...` is reported as `trusted`. There should be no `untrusted` rows for paths under your projects directory.

To prove the new prefix rule (and not a previously-cached explicit trust) is what's doing the work, do an explicit untrust round-trip on one file and confirm mise still treats it as trusted via the prefix:

```bash
mise trust --untrust "$HOME/projects/new-machine-bootstrap/mise.toml"
cd "$HOME/projects/new-machine-bootstrap" && mise trust --show | grep mise.toml
```

Expected: the line for `mise.toml` still shows `trusted`. (The explicit untrust was overridden by the `trusted_config_paths` prefix match.)

If the file shows as `untrusted`, the prefix rule is not taking effect — re-check the value of `mise settings get trusted_config_paths` and confirm it includes the user's projects directory.

- [ ] **Step 9: Restore explicit trust on the bootstrap repo's mise.toml**

The Step 8 untrust was a verification probe; restore the explicit trust so we don't leave verification residue behind:

```bash
mise trust "$HOME/projects/new-machine-bootstrap/mise.toml"
```

Expected: command exits 0 with no error. (The path is already covered by the prefix, but explicit trust is still recorded in `~/.local/state/mise/trusted-configs/` for hygiene.)

- [ ] **Step 10: Inspect the diff**

```bash
git diff roles/common/tasks/main.yml
```

Expected: a single hunk inserting the two new task definitions immediately before the `Trust mise config (Linux)` task. No other lines changed. No trailing whitespace introduced.

- [ ] **Step 11: Commit**

Stage only the modified file and invoke the commit skill:

```bash
git add roles/common/tasks/main.yml
```

Then ask the user to approve the commit and use the `/personal:commit` skill (a `git commit` invocation will be blocked by the project's pre-commit hook). Suggested commit message subject: `Auto-trust mise configs under ~/projects`. Body should mention that the change is platform-agnostic and that `~/projects` not existing on Codespaces is intentionally a no-op.

---

## Verification Summary

When this plan is complete:

1. `mise settings get trusted_config_paths` on a macOS or Linux dev host returns a list containing the user's `~/projects` path.
2. Re-running `bin/provision` reports `skipping` for the new auto-trust task (idempotent).
3. Any mise config under `~/projects` (including newly-created ones) loads without an "untrusted config" warning.
4. The existing `Trust mise config (Linux)` task, the per-worktree `mise trust` calls in `roles/common/templates/dotfiles/zshrc`, and the bash_profile equivalent are unchanged and still functional for the Codespaces case.
