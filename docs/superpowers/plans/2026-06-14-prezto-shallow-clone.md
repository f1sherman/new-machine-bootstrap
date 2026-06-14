# Prezto Shallow Clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce fresh provisioning time by making the common Prezto checkout shallow while preserving the existing Ansible git module behavior.

**Architecture:** Keep `roles/common/tasks/main.yml` responsible for installing Prezto. Add the supported `depth: 1` option to the existing `git` task and protect it with a repository policy assertion.

**Tech Stack:** Ansible `git` module, Bash policy tests, `yq`.

---

## File Structure

- Modify `roles/common/tasks/main.yml` in the existing `Clone prezto` task.
- Modify `tests/repo-policy.sh` in `run_install_checks` to assert that the Prezto clone task stays shallow.

### Task 1: Make Prezto Clone Shallow

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Modify: `tests/repo-policy.sh`

- [ ] **Step 1: Write the failing policy assertion**

Add this assertion near the existing common-role assertions in `run_install_checks` in `tests/repo-policy.sh`:

```bash
  assert_yaml_equals "$COMMON_MAIN" '.[] | select(.name == "Clone prezto") | .git.depth' "1" "common Prezto clone is shallow for fresh provisioning speed"
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
bash tests/repo-policy.sh installs
```

Expected: FAIL with this policy name:

```text
common Prezto clone is shallow for fresh provisioning speed
```

- [ ] **Step 3: Add shallow clone depth to the Prezto task**

Update the existing `Clone prezto` task in `roles/common/tasks/main.yml` to include `depth: 1`:

```yaml
- name: Clone prezto
  git:
    dest: '{{ ansible_facts["user_dir"] }}/.zprezto'
    repo: 'https://github.com/sorin-ionescu/prezto.git'
    recursive: yes
    update: yes
    depth: 1
```

- [ ] **Step 4: Run the focused policy test again**

Run:

```bash
bash tests/repo-policy.sh installs
```

Expected: PASS for the Prezto shallow-clone assertion and zero failures overall.

- [ ] **Step 5: Run Ansible syntax check**

Run:

```bash
ansible-playbook --inventory localhost, --connection local playbook.yml --syntax-check
```

Expected: syntax check passes for `playbook.yml`.

- [ ] **Step 6: Run integration policy checks**

Run:

```bash
bash tests/repo-policy.sh integration
```

Expected: PASS and zero failures, preserving the fresh provisioning timing instrumentation from the prior PR.

- [ ] **Step 7: Commit the optimization**

Run:

```bash
git add roles/common/tasks/main.yml tests/repo-policy.sh
git commit -m "Shallow clone prezto during provision"
```

Expected: commit succeeds with only the task and policy test changes.

## Self-Review

- Spec coverage: this targets the highest measured fresh CI bottleneck from PR #250, `common : Clone prezto` at 16.01 seconds.
- Correctness: the existing Ansible `git` module still owns clone/update behavior; only clone depth changes.
- Scope: no changes to Prezto runcom installation, shell configuration, or other repositories are included.
