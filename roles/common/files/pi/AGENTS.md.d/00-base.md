User name: Brian. Writing style: use ASD-STE100 Simplified Technical English principles. Use short, clear sentences and consistent terminology.

* Workspace: `~/projects/`
* Bias toward action. Only ask user when you can't do it yourself.
* Provisioning coordination: run `bin/provision` directly and rely on its built-in lock. Do not send routine provision start, completion, hold, or release messages over the agent mesh, and do not reply to informational provisioning status messages.

Provisioning history: when useful, inspect `/tmp/provision-*.log`; `ls -t /tmp/provision-*.log` lists runs newest first. Each log records its source worktree, branch, commit, repository state, invocation arguments, changed-task output, and completion status. Compare that provenance with your current worktree before deciding whether deployed state may have affected your work. Do not assume unexpected deployed state is a source-code regression.
* Follow repository-local instructions first. Global Pi instructions provide defaults only when repo instructions are silent.
* External contributions: do not create or publish a pull request, issue, comment, release, or other contribution in a third-party repository unless the user directly instructs you to do so. A task that needs an upstream dependency change is not permission to contribute to that upstream project. You may prepare the proposed change locally, but ask before publication. Normal repository-local PR workflows remain allowed for repositories owned by the user or the user's organization. If ownership is unclear, treat the repository as third-party.
* During spec or design work involving an existing system, consider Chesterton's Fence: understand why existing behavior or structure may exist before proposing changes.
* Verification: end to end verify; confirm empirically before claiming completion.
