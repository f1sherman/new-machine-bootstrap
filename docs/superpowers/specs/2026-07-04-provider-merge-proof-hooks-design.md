# Provider Merge-Proof Hooks Design

## Context

`new-machine-bootstrap` (NMB) provisions generic development-machine tooling. Its `repo-end` helper safely leaves a feature branch or worktree only after it can prove the branch has been merged. That proof currently includes GitHub and Forgejo API behavior.

Forgejo support is specific to Brian's internal repositories and host naming. It should not live in NMB core. NMB should expose a generic provider hook point instead, and consuming repos such as `home-network-provisioning` (HNP) should install provider-specific behavior.

## Goals

- Keep NMB's `repo-end` generic and reusable.
- Preserve GitHub support that is useful for NMB's public GitHub workflow.
- Remove hard-coded Forgejo/internal-host behavior from NMB.
- Add a provider-neutral `repo-end.d` phase that can prove merge status before cleanup.
- Document the extension point so internal providers can be added outside NMB.

## Non-goals

- Add first-class Forgejo support to NMB.
- Replace the existing callback directory with a new provider-specific directory.
- Build a large provider plugin framework.
- Change `repo-start` behavior.

## Design

NMB will extend the existing `repo-end.d` callback model with phases. `repo-end` will still own all cleanup sequencing, branch safety checks, and worktree deletion. Provider-specific callbacks can contribute only one thing: a pre-cleanup proof that the current branch was merged.

### Merge-proof phase

When built-in local, remote, and GitHub proof fail, `repo-end` runs executable callbacks from `~/.local/bin/repo-end.d` in lexicographic order with:

```text
--phase merge-proof
--repo-dir <current repo/worktree>
--branch <current branch>
--main-branch <main branch>
--main-path <main checkout path>
```

Exit semantics:

- `0`: proof accepted; continue cleanup.
- `1`: no proof from this callback; try the next callback.
- `2+`: hard failure; abort cleanup.

A hard failure is for unsafe or ambiguous states, such as multiple provider PRs matching the same branch, invalid API responses, or any condition where cleanup could delete unmerged work.

### Post-cleanup phase

The existing post-cleanup callback behavior remains, but callbacks receive an explicit phase:

```text
--phase post-cleanup
--repo-dir <current repo/worktree>
--branch <current branch>
--main-branch <main branch>
--main-path <main checkout path>
```

Existing callback behavior should stay compatible except for the additional `--phase` argument. Consumers that need strict argument parsing can update their callbacks to handle `post-cleanup` explicitly.

## NMB Responsibilities

NMB will:

- run merge-proof callbacks only after built-in proof fails;
- treat callback exit code `1` as no proof, not as a fatal callback failure;
- treat callback exit code `2+` as fatal;
- preserve current post-cleanup callback behavior;
- document that internal provider logic belongs in consuming repos;
- remove Forgejo-specific URL, alias, API, and token logic from `repo-end`.

NMB may keep GitHub proof support because NMB itself is GitHub-hosted and the GitHub CLI/API behavior is broadly useful.

## Consumer Responsibilities

A consuming repo such as HNP can install callbacks into `~/.local/bin/repo-end.d`. A provider callback should:

- inspect `--phase` and only perform provider proof during `merge-proof`;
- return `1` for non-matching providers or missing non-required credentials;
- return `2+` for ambiguous or unsafe states;
- print a concise proof message when it returns `0`;
- avoid hard-coded assumptions in NMB.

## Testing Strategy

NMB behavior tests should cover:

- no merge-proof callbacks preserves current failure behavior;
- one callback returning `1` falls through to a later callback;
- a callback returning `0` allows cleanup;
- a callback returning `2` aborts cleanup and preserves the worktree or branch;
- post-cleanup callbacks still run in lexicographic order;
- callback stdout remains safe in `--print-path` mode;
- Forgejo-specific code paths are gone from NMB tests and implementation.

These should be shell behavior tests using fake repositories and executable callbacks. They should not rely on grepping implementation text except where a literal string is itself the policy under test.

## Guidance Updates

NMB guidance should state:

- NMB provides generic repo lifecycle helpers and extension points.
- Internal forge/provider behavior must be installed by the consuming repo through `repo-end.d`.
- The `merge-proof` phase is the supported pre-cleanup extension point.
- Hard-coded internal hosts, such as Brian's Forgejo instance, do not belong in NMB.

## Migration

1. Add tests for the phased `repo-end.d` contract.
2. Implement the merge-proof phase in `repo-end`.
3. Update post-cleanup callback invocation to include `--phase post-cleanup`.
4. Remove Forgejo-specific helper functions and tests from NMB.
5. Update NMB guidance.
6. Coordinate with HNP to add the internal Forgejo callback.
