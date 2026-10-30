# Concrete PR benefits

## Problem and benefit

The existing work-selection guidance requires personal value before starting work. It does not require agents to state that value in a PR. A reviewer can therefore receive a technically detailed description without a clear reason to spend time on the change.

## Design

Require a `## Benefit to Brian` section near the start of every PR description, including documentation and maintenance changes. Name the affected task, the practical change, and its benefit. Distinguish expected gains from measured results. Include material costs, rollout requirements, and limits. If the benefit is not demonstrated, say so and reconsider agent-proposed work.

Preserve work-selection, verification, isolation, and publication rules. Change only repository instructions. Do not modify shared skills, deployed files, or runtime configuration.

## Native execution plan

1. Read repository instructions and confirm public visibility. Create an isolated worktree with repo-start.
2. Add the PR-benefit contract below work-selection guidance in CLAUDE.md. AGENTS.md remains its symlink.
3. Run a bounded description-generation diagnostic with matched baseline, full guidance, each new component removed, and an empty-policy control. Keep private inputs outside this repository. Report limitations rather than claiming general reliability.
4. Inspect the full diff and obtain independent review. Commit the instructions and this spec and plan. Open a PR. Do not merge or provision documentation-only changes.

## Throughput checkpoint

A short repository-local contract is sufficient. Shared-skill rewrites and heading-presence tests would add maintenance without demonstrating a user benefit.
