# Provision Log Provenance Design

## Goal

Help agents determine whether another provisioning run may have changed deployed state relevant to their work, without adding routine coordination messages or mandatory inspection steps.

## Scope

- Add source provenance to every `/tmp/provision-*.log`.
- Extend managed Pi and Claude guidance with instructions for finding and interpreting provisioning history.
- Leave the decision to inspect other runs to the agent.
- Keep agent-mesh behavior unchanged.

## Log Provenance

At the beginning of each provisioning log, `bin/provision` will record:

- the canonical source worktree path;
- the branch name, or a detached-HEAD marker;
- the full commit SHA;
- whether the source repository was clean or dirty;
- the invocation arguments; and
- the start timestamp.

The existing Ansible output, changed-task summary, errors, elapsed time, and completion messages remain unchanged. Arguments must use the same secret-redaction behavior as the existing logged Ansible command.

When Git metadata is unavailable, the corresponding fields will use an explicit `unknown` value rather than preventing provisioning.

## Managed Agent Guidance

The managed Pi and Claude base fragments will explain that:

- provisioning history is stored in `/tmp/provision-*.log`;
- `ls -t /tmp/provision-*.log` lists the logs newest first;
- each log identifies its source worktree, branch, commit, repository state, arguments, changed-task output, and completion status;
- an agent inspecting another run should compare that provenance with its current worktree before deciding whether deployed state may have affected its work; and
- unexpected deployed state should not automatically be treated as a source-code regression.

The guidance will not prescribe when inspection is required and will not add routine status messages, replies, receipts, confirmation commands, or agent-mesh coordination.

## Portability and Failure Behavior

The implementation will remain compatible with stock macOS Bash 3.2 and Debian Bash. Git provenance lookup failures will be non-fatal. Logging provenance must not weaken the existing provision lock or delay lock acquisition.

## Verification

Automated coverage will run `bin/provision` with controlled command stubs and verify that the generated log records the source worktree, branch or detached state, commit, repository state, arguments, and start timestamp. Tests will verify behavior rather than exact managed-guidance prose.

Existing concurrency, Pi assembly, CI inventory, shell syntax, and provisioning checks must continue to pass.
