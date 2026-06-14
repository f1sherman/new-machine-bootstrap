# Fresh Provisioning Speed Campaign Design

## Purpose

Speed up new-machine-bootstrap provisioning as a campaign, starting with fresh-machine impact. The first source of truth is the Linux fresh provisioning path exercised by the GitHub Actions integration workflow. macOS steady-state provisioning remains a regression guard, not the first optimization target.

## Context

The repository provisions macOS machines and Debian development hosts through `bin/provision`, which bootstraps Ansible and runs `playbook.yml`. The integration workflow runs on `ubuntu-latest`, checks out the repository, runs `bin/provision`, then verifies installed tools and helper behavior.

A local macOS check-mode profile on June 14, 2026 took 3 minutes 32 seconds. The largest observed macOS steady-state costs were macOS defaults, one-time cleanup loops, many per-file copy operations, and cask/package checks. These are useful campaign data points, but the user has directed the first phase to focus on fresh-machine impact.

## Goals

- Make fresh Linux provisioning faster without weakening correctness.
- Add measurement good enough to identify and compare bottlenecks across PRs.
- Keep `bin/provision` as the single supported entrypoint.
- Optimize in small PRs with attributable timing deltas.
- Preserve existing version assertions, package pinning, and idempotence guarantees.

## Non-Goals

- Do not redesign the provisioning system away from Ansible.
- Do not skip required fresh-machine setup for speed.
- Do not make macOS the primary benchmark in the first phase.
- Do not merge broad role refactors unless they directly support measured speed work.

## Measurement Design

The primary benchmark is the `Run provisioning` step in `.github/workflows/integration-test.yml`.

The first campaign PR should enable Ansible task timing for that step, using `profile_tasks` or an equivalent callback that prints per-task durations in CI logs. This gives every later optimization a reliable source of fresh-machine timing evidence.

Each optimization PR should record:

- The target bottleneck.
- The before timing source.
- The after timing source.
- Any tradeoff or skipped alternative.

Local macOS measurement remains useful as a secondary guard:

```bash
ANSIBLE_CALLBACKS_ENABLED=profile_tasks ansible-playbook --inventory localhost, --connection local playbook.yml --check --diff
```

This local command should not be the primary success metric for the first phase.

## Optimization Sequence

### 1. Instrument Fresh Provisioning

Add task profiling to the integration provisioning step while preserving the existing `bin/provision` entrypoint. CI logs should show a task recap or comparable timing summary after provisioning.

### 2. Optimize Linux Fresh Install Bottlenecks

Use the fresh CI timing recap to pick targets. Likely areas to validate first:

- `roles/linux/tasks/install_packages.yml`
- `roles/common/tasks/install_github_binary.yml`
- mise Node, aube, and global package setup
- nvim bootstrap/plugin setup
- repeated file and skill deployment tasks that dominate fresh runs

### 3. Batch Owned File Deployment Where Safe

If CI timing shows Ansible per-file overhead as a fresh-machine bottleneck, replace groups of owned file tasks with narrower bulk operations or manifest-backed helpers. Any batching must preserve permissions, destination paths, and managed-file ownership boundaries.

### 4. Remove or Guard One-Time Migration Work

If cleanup loops appear in fresh or steady-state profiles and no longer protect current machines, either remove them or guard them behind a cheap existence check. Cleanup must never remove files that can be user-owned or managed by another provisioner.

## Correctness Rules

- Fresh-machine correctness beats speed.
- Fast paths must be backed by a version pin, manifest, sentinel, direct file check, or tool version check.
- Errors must fail visibly; no silent best-effort skips.
- Version verification in the integration workflow remains authoritative for installed tools.
- The CI test inventory check must continue to reference every tracked test-like file.
- Any workflow timing change must still run `bin/provision`; direct `ansible-playbook` invocation is not a replacement for the integration entrypoint.

## Testing

Every implementation PR should run the relevant subset of:

```bash
ansible-playbook --inventory localhost, --connection local playbook.yml --syntax-check
bash tests/ci-test-inventory.sh
bash tests/repo-policy.sh all
ANSIBLE_CALLBACKS_ENABLED=profile_tasks ansible-playbook --inventory localhost, --connection local playbook.yml --check --diff
```

The primary proof for fresh-machine impact is the GitHub Actions integration run.

## Rollout

Ship the campaign as multiple small PRs. The first PR should add timing visibility. Later PRs should each optimize one measured bottleneck and include timing proof in the PR description or proof comment.

Continue until timing recaps show that remaining bottlenecks are either external network/package manager costs, too risky to optimize without larger redesign, or below the threshold where further changes are worth the maintenance cost.
