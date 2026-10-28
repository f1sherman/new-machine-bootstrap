# BB Retained Cleanup Implementation Plan

> Use Native execution with `superpowers:executing-plans`. The PR workflow owns one final fresh-context review. Do not offer an execution-mode choice.

**Goal:** Return an honest retained-by-owner result for verified BB worktrees without a forge dependency.

**Architecture:** Change only the early BB ownership branch in `repo-end`. Leave standalone cleanup below it unchanged.

**Tech Stack:** Bash, Ruby test helpers, real temporary Git repositories.

**Spec:** `docs/superpowers/specs/2026-10-28-bb-retained-cleanup-design.md`.

**Status:** Self-reviewed and approved.

## Global constraints

- No cleanup, archival, callbacks, remote lookup or branch mutation in the retained path.
- A successful retained result is not proof of a merged PR.
- Ownership uncertainty and BB `--closed` remain refusals.
- Non-BB cleanup semantics stay unchanged.
- No private provider identities or captures in the public repository.

## Review focus

- Different origins and unavailable forge clients must not affect verified retention.
- Dirty and untracked content must survive byte-for-byte.
- Misbound or unavailable BB context must not fall through to Git cleanup.
- Output with `--print-path` must preserve the caller's checkout path.
- No retained path may execute cleanup or proof callbacks.

## Task 1: Make verified BB retention provider-independent

**Files:** `roles/common/files/bin/repo-end`, `tests/repo-lifecycle.sh`, and user documentation if an existing lifecycle section applies.

**Interface:** normal `repo-end [--print-path]` returns 0 for verified BB ownership, reports retention and does not establish PR state. `--closed` still returns nonzero. No flags or provider APIs are added.

- [x] Establish a passing lifecycle baseline and capture the exact deployed artifact privately.
- [x] Extend the real-worktree fixture. The unmodified helper fails at the expected provider-independent-retention assertion; sentinel and identity checks remain behavioral.
- [x] Replace the early GitHub-specific proof path with the retained-by-owner no-op. Keep `--closed` and ownership error handling unchanged. Document that success does not prove merge state.
- [x] Run lifecycle, repo-end callback and repo-start callback suites; all pass. The command guard rejects separate `bash -n` invocations of the source helper, but the full production helper executes under Bash in the passing suites.
- [x] Execute the closest permitted boundary with the candidate source, actual Git worktrees and BB ownership fixtures. Direct live candidate execution is rejected by the command guard; do not bypass it. The installed helper is unchanged. Original live replay remains a post-merge provisioning check.
- [ ] Run the PR workflow's fresh-context review, resolve material findings, commit verified changes and create the public PR. Report live installation as pending until merge.
