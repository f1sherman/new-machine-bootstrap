# Install the pstack cleanup dependency

Status: self-approved.

## Goal and cause

The managed pstack installation omits cursor-team-kit's deslop skill. Poteto-mode requires it before commits. The adapter correctly stops rather than claiming that missing cleanup passed. Install the exact upstream dependency, not a substitute prompt.

## Scope and assumptions

Use the existing cursor/plugins SHA in tool_versions.git_commits.pstack for both packages. Preserve the complete deslop directory and cursor-team-kit MIT license. Do not install the full Cursor plugin, change skill text, weaken missing-capability checks, change models, or address the application issue that exposed this gap. No prompt optimization is proposed; upstream instruction bytes stay unchanged.

## Approaches

1. Recommended: extend the existing pinned snapshot with external/deslop and external/LICENSE. Deploy this selected dependency through the existing managed-skill linker to Pi, Claude Code, and Codex. Existing Renovate updates maintain one atomic source revision.
2. Install all of cursor-team-kit. This adds unrelated tools and harness-specific integrations.
3. Substitute a local cleanup prompt. This changes workflow behavior and needs behavior evals, while the real skill is small and portable.

## Boundaries

The updater fetches pstack and the selected cursor-team-kit paths from one exact commit. Its existing archive validation, checksums, transactional replacement, and lock apply to both. A missing skill or license, symlink, or other unsupported archive entry must fail before replacing the previous snapshot. The external subtree is deployed as a separate managed skill tree. Only deslop is discoverable there; the full pstack reference remains outside skill discovery. Local safety policy remains authoritative.

## Verification and rollout

Run the existing updater safety suite before and after the change. Extend unsafe-input cases to cover the new selected source boundary. Generate and check the actual pinned snapshot. Provision managed-skills locally and verify all three harness paths resolve to exact upstream bytes. Repeat provisioning to check idempotence. Use an isolated temporary HOME with the production linker to verify fresh installation too. No new test for declarative task presence. A full application workflow remains owned by its original thread; this task proves dependency installation, not that application's repair.

Use a feature worktree and GitHub PR in this repository. Do not merge. Existing sessions can need reload or a fresh session before the new skill enters their catalog.
