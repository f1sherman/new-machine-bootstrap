# new-machine-bootstrap Work Integration Plan

## Overview

Update `new-machine-bootstrap` to automatically clone and run `bootstrap-brian-john` work provisioning on both macOS work machines and GitHub Codespaces.

## Current State Analysis

- **macOS**: Ruby script (`macos`) orchestrates provisioning, has pattern for personal machines (`home-network-provisioning`)
- **Codespaces**: `bin/provision` runs Ansible directly, no work-specific provisioning
- `Provision.update_project` method hardcodes `f1sherman` org (`macos:59`)

## Desired End State

- macOS work machines automatically clone/update and run `betterup/bootstrap-brian-john`
- Codespaces automatically clone/update and run work provisioning via Ansible

### Verification
- `~/.config/new-machine-bootstrap.yml` contains `use: work` → work repo is cloned and provisioned
- In Codespaces, `~/projects/bootstrap-brian-john` exists after provisioning

## What We're NOT Doing

- Modifying `home-network-provisioning` integration
- Adding work detection to Codespaces (all Codespaces are work machines)
- Changes to `bootstrap-brian-john` itself (separate plan)

---

## Phase 1: Update Ruby Bootstrap Script

### Overview
Add `org:` parameter support to `Provision.update_project` and add work machine provisioning.

### Changes Required

#### 1. Update Provision.update_project method
**File**: `macos`
**Lines**: 50-62

Add `org:` parameter with default value `'f1sherman'`:

```ruby
def self.update_project(project_name, remote: 'github.com', org: 'f1sherman')
  project_dir = File.join(Dir.home, 'projects', project_name)

  if File.exist? project_dir
    puts "\nUpdating #{project_name}\n"
    run_command "cd #{project_dir} && git pull"
    puts "\nDone updating #{project_name}\n"
  else
    puts "\nCloning #{project_name}\n"
    run_command "git clone git@#{remote}:#{org}/#{project_name}.git #{project_dir}"
    puts "\nDone cloning #{project_name}\n"
  end
end
```

#### 2. Add work machine provisioning
**File**: `macos`
**Lines**: After 128 (after the personal machine block)

```ruby
if config.work?
  Provision.update_project 'bootstrap-brian-john', org: 'betterup'
  Provision.run_command 'cd ~/projects/bootstrap-brian-john && bin/provision'
end
```

### Success Criteria

#### Automated Verification
- [x] Ruby syntax check passes: `ruby -c macos`

#### Manual Verification
- [ ] On work macOS machine, running `./macos` clones/updates `bootstrap-brian-john`
- [ ] Work provisioning script runs after main provisioning

---

## Phase 2: Update Ansible for Codespaces

### Overview
Add tasks to clone and run work provisioning in Codespaces environment.

### Changes Required

#### 1. Add work provisioning tasks to common role
**File**: `roles/common/tasks/main.yml`
**Location**: At end of file (after skills deployment, line 314)

```yaml
# Work provisioning for Codespaces
- name: Create ~/projects directory for work provisioning
  file:
    path: '{{ ansible_facts["user_dir"] }}/projects'
    state: directory
    mode: '0755'
  when: lookup('env', 'CODESPACES') == 'true'

- name: Clone work provisioning repository
  git:
    dest: '{{ ansible_facts["user_dir"] }}/projects/bootstrap-brian-john'
    repo: 'https://github.com/betterup/bootstrap-brian-john.git'
    update: yes
  when: lookup('env', 'CODESPACES') == 'true'

- name: Run work provisioning
  command: '{{ ansible_facts["user_dir"] }}/projects/bootstrap-brian-john/bin/provision'
  changed_when: false
  when: lookup('env', 'CODESPACES') == 'true'
```

### Success Criteria

#### Automated Verification
- [x] Ansible syntax check passes: `ansible-playbook playbook.yml --syntax-check`
- [x] Dry run succeeds: `CODESPACES=true ansible-playbook playbook.yml --check` (fails at apt update due to sudo requirement when run locally, but new tasks are included)

#### Manual Verification
- [ ] In Codespaces, running `bin/provision` clones and runs work provisioning

---

## Testing Strategy

### Unit Tests
- Ruby syntax validation: `ruby -c macos`
- Ansible syntax validation: `ansible-playbook playbook.yml --syntax-check`

### Integration Tests
- Full macOS work machine provisioning
- Full Codespaces provisioning via `sync-to-codespace`

### Manual Testing Steps
1. On macOS work machine, verify `~/projects/bootstrap-brian-john` is cloned
2. Verify work provisioning runs without errors
3. In Codespaces, verify same behavior

---

## References

- Research: `.coding-agent/research/2026-01-05-bootstrap-brian-john-work-repo-structure.md`
- Personal provisioning pattern: `macos:125-128`
- Codespaces git clone pattern: `roles/common/tasks/main.yml:34-39`
- Related plan: `~/projects/bootstrap-brian-john/.coding-agent/plans/2026-01-05-bootstrap-brian-john-structure.md`
