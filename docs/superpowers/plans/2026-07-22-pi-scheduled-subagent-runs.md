# Pi Scheduled Subagent Runs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable explicitly requested Pi scheduled subagent runs on every host managed by the common Ansible role.

**Architecture:** Store one deterministic pi-subagents JSON config in the common role. Provision its parent directory and file unconditionally, then enforce the source and Ansible contract with a focused shell test referenced by CI.

**Tech Stack:** Ansible YAML, JSON, Bash, Ruby YAML/JSON parsing, GitHub Actions

## Global Constraints

- Install on every macOS and Debian host managed by the common role.
- The managed config must contain only `{ "scheduledRuns": { "enabled": true } }`.
- Install `~/.pi/agent/extensions/subagent/` with mode `0755` and `config.json` with mode `0644`.
- Do not schedule jobs or change lateness and pending-job limits.
- Do not add deployed-state merging or compatibility inference.
- Keep public repository content free of private organization, repository, ticket, employee, and environment references.

---

### Task 1: Provision Scheduled-Run Configuration

**Files:**
- Create: `tests/pi-scheduled-subagent-runs.sh`
- Create: `roles/common/files/pi/extensions/subagent/config.json`
- Modify: `roles/common/tasks/main.yml` after the global extensions directory task
- Modify: `.github/workflows/integration-test.yml` near the Pi provisioning contract steps

**Interfaces:**
- Consumes: Ansible common-role file lookup rooted at `roles/common/files/`.
- Produces: `~/.pi/agent/extensions/subagent/config.json` with `scheduledRuns.enabled` set to JSON boolean `true`.

- [ ] **Step 1: Write the failing provisioning contract**

Create `tests/pi-scheduled-subagent-runs.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
main_tasks="$repo_root/roles/common/tasks/main.yml"
config="$repo_root/roles/common/files/pi/extensions/subagent/config.json"

ruby -rjson -ryaml - "$main_tasks" "$config" <<'RUBY'
main_tasks = YAML.load_file(ARGV.fetch(0))
config = JSON.parse(File.read(ARGV.fetch(1)))
raise "unexpected scheduled-run config" unless config == { "scheduledRuns" => { "enabled" => true } }

by_name = main_tasks.filter_map { |task| [task["name"], task] if task.is_a?(Hash) && task["name"] }.to_h
directory = by_name["Create Pi subagent configuration directory"] or abort "missing subagent configuration directory task"
file = directory.fetch("file")
raise "wrong subagent directory" unless file["path"] == "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/subagent"
raise "wrong subagent directory state" unless file["state"] == "directory"
raise "wrong subagent directory mode" unless file["mode"] == "0755"

install = by_name["Enable Pi scheduled subagent runs"] or abort "missing scheduled-run configuration task"
copy = install.fetch("copy")
raise "wrong scheduled-run source" unless copy["src"] == "pi/extensions/subagent/config.json"
raise "wrong scheduled-run destination" unless copy["dest"] == "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/subagent/config.json"
raise "wrong scheduled-run mode" unless copy["mode"] == "0644"
raise "scheduled-run task must apply to all common-role hosts" if install.key?("when")
RUBY

printf 'Pi scheduled subagent run provisioning checks complete\n'
```

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```bash
bash tests/pi-scheduled-subagent-runs.sh
```

Expected: non-zero exit because `roles/common/files/pi/extensions/subagent/config.json` does not exist.

- [ ] **Step 3: Add the minimal managed config**

Create `roles/common/files/pi/extensions/subagent/config.json`:

```json
{
  "scheduledRuns": {
    "enabled": true
  }
}
```

- [ ] **Step 4: Add unconditional common-role provisioning tasks**

In `roles/common/tasks/main.yml`, immediately after `Create pi-coding-agent global extensions directory`, add:

```yaml
- name: Create Pi subagent configuration directory
  file:
    path: "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/subagent"
    state: directory
    mode: '0755'

- name: Enable Pi scheduled subagent runs
  copy:
    src: pi/extensions/subagent/config.json
    dest: "{{ ansible_facts['user_dir'] }}/.pi/agent/extensions/subagent/config.json"
    mode: '0644'
```

- [ ] **Step 5: Run the focused contract and verify GREEN**

Run:

```bash
bash tests/pi-scheduled-subagent-runs.sh
```

Expected: exit 0 and `Pi scheduled subagent run provisioning checks complete`.

- [ ] **Step 6: Reference the contract from CI**

In `.github/workflows/integration-test.yml`, immediately after `Verify Pi main worktree guard provisioning`, add:

```yaml
      - name: Verify Pi scheduled subagent run provisioning
        run: bash tests/pi-scheduled-subagent-runs.sh
```

- [ ] **Step 7: Run repository validation**

Run:

```bash
bash tests/pi-scheduled-subagent-runs.sh
bash tests/ci-test-inventory.sh
ansible-playbook --syntax-check playbook.yml
git diff --check
```

Expected: focused contract and CI inventory report pass; Ansible reports `playbook: playbook.yml`; diff check exits 0.

- [ ] **Step 8: Commit the implementation**

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Enable Pi scheduled subagent runs" \
  tests/pi-scheduled-subagent-runs.sh \
  roles/common/files/pi/extensions/subagent/config.json \
  roles/common/tasks/main.yml \
  .github/workflows/integration-test.yml
```

- [ ] **Step 9: Provision and verify the deployed behavior**

Run from the feature worktree:

```bash
bin/provision
jq -e '. == {"scheduledRuns":{"enabled":true}}' "$HOME/.pi/agent/extensions/subagent/config.json"
```

Expected: provisioning completes with `failed=0`; `jq` exits 0. Start a fresh Pi process before runtime verification because the current extension process loaded configuration before provisioning. In that fresh process, run subagent diagnostics or `schedule-list` and confirm scheduling is enabled without creating a job.
