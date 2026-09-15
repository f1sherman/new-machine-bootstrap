# Automatic pull request guidance design

## Goal

Make pull request creation the default completion step for code changes in repositories owned by Brian or his employer. The agent must not stop after editing, verification, or commit when it can safely publish the pull request.

## Assumptions

- The existing external-contribution rule remains authoritative for repositories that Brian and his employer do not own.
- The change applies to the managed Claude and Pi global instruction files.
- Existing provisioning already installs and assembles both files, so no Ansible task changes are necessary.

## Options considered

1. **Strengthen the pull request rule in both managed instruction files.** This is direct, keeps both agents consistent, and preserves the existing external-publication guard. This is the recommended option.
2. Add a new shared fragment. This would isolate the rule, but it would add file and provisioning complexity for one short instruction.
3. Change only the Pi instruction file because Claude already has a weaker pull request rule. This would fix the immediate gap but leave inconsistent wording and intent.

## Design

Add a pull request rule to both base instruction files. The rule will state that a request to make code changes in a first-party repository also authorizes the agent to create the pull request automatically after verification and commit. It will tell the agent not to stop at local changes or a commit and not to ask for separate pull request approval.

The rule will explicitly defer to the existing external-contribution rule. That rule requires authorization before publication to a public repository not owned by Brian or his employer.

No automated test will assert exact prose. Such a test would repeat static configuration and would not provide material protection. Verification will use provisioning and direct checks of the assembled files in the home directory.

## Success criteria

- Both managed base instruction files contain equivalent automatic pull request guidance.
- The guidance preserves the external-publication exception.
- `bin/provision` completes successfully from the feature worktree.
- The assembled home-directory instruction files contain the new guidance.
- A draft pull request contains the verified and committed change.
