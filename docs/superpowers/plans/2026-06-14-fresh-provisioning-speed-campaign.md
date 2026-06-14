# Fresh Provisioning Speed Campaign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make fresh Linux provisioning in CI emit Ansible task timing so future speed PRs can target measured bottlenecks.

**Architecture:** Keep `bin/provision` as the integration entrypoint and configure the GitHub Actions step environment to enable Ansible's `profile_tasks` callback. Add a repository policy assertion so future workflow edits cannot remove fresh provisioning timing by accident.

**Tech Stack:** GitHub Actions YAML, Bash policy tests, `yq`, Ansible callback configuration.

---

## File Structure

- Modify `.github/workflows/integration-test.yml` to add `ANSIBLE_CALLBACKS_ENABLED: profile_tasks` to the existing `Run provisioning` step environment.
- Modify `tests/repo-policy.sh` in `run_integration_checks` to assert that the integration workflow keeps profiling enabled for `Run provisioning`.
- Use existing CI inventory coverage; no new test file is needed because `tests/repo-policy.sh` is already referenced by `.github/workflows/integration-test.yml`.

### Task 1: Guard Fresh Provisioning Profiling

**Files:**
- Modify: `.github/workflows/integration-test.yml`
- Modify: `tests/repo-policy.sh`

- [ ] **Step 1: Write the failing policy assertion**

Add this assertion to `run_integration_checks` in `tests/repo-policy.sh`, immediately after the existing `GITHUB_TOKEN` assertion:

```bash
  assert_yaml_equals "$INTEGRATION_WORKFLOW" '.jobs.provision.steps[] | select(.name == "Run provisioning") | .env.ANSIBLE_CALLBACKS_ENABLED' 'profile_tasks' "integration workflow enables Ansible task profiling during provisioning"
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
bash tests/repo-policy.sh integration
```

Expected: FAIL with this policy name:

```text
integration workflow enables Ansible task profiling during provisioning
```

- [ ] **Step 3: Enable profiling in the integration workflow**

Update `.github/workflows/integration-test.yml` so the `Run provisioning` step has both environment variables:

```yaml
      - name: Run provisioning
        run: bin/provision
        env:
          ANSIBLE_CALLBACKS_ENABLED: profile_tasks
          GITHUB_TOKEN: ${{ github.token }}
```

- [ ] **Step 4: Run the focused policy test again**

Run:

```bash
bash tests/repo-policy.sh integration
```

Expected: PASS for the profiling assertion and zero failures overall.

- [ ] **Step 5: Run workflow inventory coverage**

Run:

```bash
bash tests/ci-test-inventory.sh
```

Expected: PASS and zero failures, proving no new unreferenced test file was introduced.

- [ ] **Step 6: Run Ansible syntax check**

Run:

```bash
ansible-playbook --inventory localhost, --connection local playbook.yml --syntax-check
```

Expected: syntax check passes for `playbook.yml`.

- [ ] **Step 7: Commit the instrumentation change**

Run:

```bash
git add .github/workflows/integration-test.yml tests/repo-policy.sh
git commit -m "Profile integration provisioning"
```

Expected: commit succeeds with only the workflow and policy test changes.

## Self-Review

- Spec coverage: Task 1 implements the first campaign PR from the spec by adding timing visibility to the fresh integration provisioning step while preserving `bin/provision`.
- Correctness: the policy test asserts the exact workflow step environment, so the profiling wire-up is protected against accidental removal.
- Scope: no package or role optimization is included in this first implementation plan; those should follow after CI produces fresh provisioning task timing.
