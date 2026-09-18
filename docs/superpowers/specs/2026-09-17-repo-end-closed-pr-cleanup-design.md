# repo-end closed PR cleanup design

## Status

Self-approved on 2026-09-17.

## Goal

Add an explicit `repo-end --closed` mode that safely removes a clean, fully
published branch only after proving that its matching pull request is closed
without merge.

## Non-goals

- Do not weaken normal `repo-end` merge proof.
- Do not treat a closed pull request as merged.
- Do not add private Forgejo host logic to this repository.
- Do not infer closure from a missing remote branch or equivalent code on main.

## Assumptions

- A local branch can be behind its remote branch, but it cannot contain commits
  absent from the remote branch.
- The remote feature branch must still exist so `repo-end` can prove all local
  commits were published and can associate the branch name with a pull request.
- GitHub is the only built-in platform integration. Forgejo and other providers
  use the existing callback directory.
- Exactly one closed, unmerged pull request with the current head branch and
  configured main base branch is unambiguous proof.

## Recommended approach

Keep merged and closed cleanup as separate policies. Parse `--closed` into an
explicit cleanup mode. After the existing dirty-tree and fetch checks, closed
mode validates the remote feature branch before it calls any provider:

1. The remote feature branch exists.
2. Local `HEAD` is an ancestor of the remote feature branch.
3. A local-ahead or diverged branch stops cleanup.

Then query GitHub when the origin URL identifies GitHub. Accept only one pull
request that is closed, unmerged, and matches both head and base branch names.
A malformed response, query failure, zero matches, an open pull request, or
multiple matches does not prove closure. Multiple matches are a hard ambiguity
and must not fall through to callbacks.

If built-in proof is unavailable, run callbacks with `--phase closed-proof`.
Use the merge-proof callback contract: exit 0 proves closure, exit 1 means no
proof, and exit 2 or higher aborts cleanup. This gives Forgejo consumers a
provider-owned proof path without restoring private forge logic to NMB.

After proof, use the existing main update, worktree removal, local branch
removal, remote branch deletion, `post-cleanup` callbacks, terminal-state
completion, and final path output. Print a clear closed-PR cleanup message.

## Alternatives considered

### Treat closed pull requests as merge proof

This would reuse the current proof path, but it would erase the distinction
between integrated work and intentionally abandoned work. It could weaken the
normal command's data-loss protection. Rejected.

### Add built-in GitHub and Forgejo API clients

This gives direct platform support, but repository policy assigns private forge
behavior to callbacks. It would also duplicate provider authentication and host
mapping. Rejected in favor of GitHub plus the generic callback contract.

### Allow cleanup when the remote branch is missing

A closed platform pull request could still identify the branch, but a missing
remote ref cannot prove that local commits were published. This conflicts with
the fail-closed requirement for local-only state. Rejected.

## Interfaces

- CLI: `repo-end [--closed] [--print-path]`.
- Callback phase: `--phase closed-proof` with the existing repository, branch,
  main branch, and main path arguments.
- Exit behavior remains nonzero when proof or safety validation fails.
- Plain `repo-end` behavior remains unchanged.

## Error handling

- Reject detached HEAD through the existing check.
- Reject dirty current or main worktrees through existing checks.
- Reject fetch failure before using remote or platform state.
- Reject a missing remote feature branch in closed mode.
- Reject local-ahead and diverged feature branches before provider callbacks.
- Reject open, merged, missing, malformed, unavailable, or ambiguous platform
  state unless a non-ambiguous provider callback supplies proof where allowed.
- Keep local cleanup successful if remote branch deletion fails, with the
  existing warning.

## Testing and verification

Add lifecycle tests that execute the production script and prove:

- Plain `repo-end` rejects a closed, unmerged branch.
- `repo-end --closed` accepts exactly one matching GitHub pull request and
  removes the worktree and both branch refs.
- GitHub ambiguity preserves the worktree.
- A local-ahead branch is rejected before a successful callback can override
  the safety check.
- Existing merged cleanup tests remain green.

Add callback tests that prove `closed-proof` uses the existing callback
arguments and that `post-cleanup` still runs after closed cleanup. Run the full
lifecycle and callback suites, shell syntax checks, Ansible syntax validation,
and provisioning.

## Rollout

Provision the updated repository after verification. No migration is needed.
Existing callers that do not pass `--closed` keep the current behavior.
