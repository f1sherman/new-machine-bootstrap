# Protect Ignored Superpowers Docs Design

**Date:** 2026-07-27

## Problem

Agent guidance says that specs and plans under `docs/superpowers/` should remain local when that path is ignored. Pi and Claude hooks also block direct commands such as `git add -f docs/superpowers/specs/example.md`.

The commit workflow can still bypass those protections. The commit skill tells its committer to retry ignored files with `--force`, and `commit.sh --force` runs `git add --force` internally. The agent hook sees the wrapper command rather than the nested Git command, so an ignored spec or plan can still be committed. Repository guidance also says to always commit specs and plans without stating the ignored-path exception.

## Goals

- Prevent `commit.sh` from force-adding ignored files under `docs/superpowers/`.
- Preserve ordinary commits of `docs/superpowers/` when that path is not ignored.
- Preserve explicit force-add support for unrelated ignored files.
- Align active repository and commit-skill guidance with the enforced behavior.
- Retain the existing Pi and Claude direct-command hooks as defense in depth.

## Non-goals

- Installing or configuring a global Git hook.
- Blocking commits of tracked `docs/superpowers/` files merely because an ignore rule also matches the directory.
- Removing `.coding-agent/` guidance, files, or workflow support. That obsolete system will be removed completely in a separate pull request.
- Changing upstream Superpowers skills.

## Design

### Commit-wrapper enforcement

The shared commit wrapper and its Pi-managed copy will classify each ignored input before staging it. If an ignored input resolves inside the repository's `docs/superpowers/` directory, the wrapper will exit nonzero even when `--force` was supplied.

The error will explain that `docs/superpowers/` is intentionally local when ignored and must not be force-added. The wrapper will perform this validation before staging any input so a rejected mixed-file invocation does not partially stage other files.

Path comparison will use repository-relative paths rather than matching an arbitrary string. This covers normal relative paths, `./`-prefixed paths, and absolute paths while avoiding false positives for similarly named directories outside the repository.

For all other inputs, current behavior remains unchanged:

- ignored input without `--force`: reject and suggest `--force`;
- ignored input with `--force`: stage with `git add --force`;
- nonignored input: stage with ordinary `git add`;
- nonignored `docs/superpowers/` input: stage and commit normally.

### Guidance alignment

Update each active commit-skill instruction and the Claude committer instructions so the general force-add retry has one explicit exception: never force-add ignored `docs/superpowers/` files.

Update repository `AGENTS.md` so specs and plans are committed under `docs/superpowers/` only when that path is not ignored. Remove `.coding-agent/` as an alternative spec or plan location from that rule. Broader `.coding-agent/` removal remains separate.

The existing base agent guidance, spec skills, Pi managed hook, and Claude `PreToolUse` hook already state or enforce the intended policy and will remain in place.

### Why not a global Git hook

Git has no pre-add hook. A pre-commit hook could reject a force-added file after staging, but provisioning a global `core.hooksPath` would interfere with repositories that manage their own hooks. Enforcing the rule in the managed commit wrapper closes the observed bypass without changing unrelated repositories' Git hook behavior.

## Testing

Add behavioral tests using disposable Git repositories:

1. Ignored `docs/superpowers/` input with `--force` exits nonzero, creates no commit, and stages none of the invocation's files.
2. A nonignored `docs/superpowers/` input commits successfully.
3. An unrelated ignored input still commits successfully with `--force`.
4. Relative, `./`-prefixed, and absolute superpowers-doc paths receive the same protection.
5. Existing Pi and Claude direct-force-add hook tests continue to pass.

Run provisioning from the feature worktree, then verify the deployed Pi commit wrapper rejects an ignored `docs/superpowers/` file end to end while preserving force-add behavior for an unrelated ignored file.

## Rollout

Provision the managed commit skills and guidance through `bin/provision`. No migration is needed. Repositories that track `docs/superpowers/` continue to behave as before; repositories that ignore it gain a hard stop in the standard commit path.
