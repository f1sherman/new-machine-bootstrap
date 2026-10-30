# Concrete PR benefits

## Problem and benefit

The existing work-selection guidance requires personal value before starting work. It does not require agents to state that value in a PR. A reviewer can therefore receive a technically detailed description without a clear reason to spend time on the change.

## Design

Require a `## Benefit to Brian` section near the start of every PR description, including documentation and maintenance changes. Name the affected task, the practical change, and its benefit. Require exactly one primary category from `time-saved`, `capability-added`, `risk-reduced`, and `cost-reduced`. Additional categories need their own concrete explanations. Reliability and maintenance describe work, not separate benefit categories. Distinguish expected gains from measured results. Include material costs, rollout requirements, and limits. If no category honestly applies, write `Benefit not demonstrated`, explain why the change is still proposed, and reconsider agent-proposed work.

Preserve work-selection, verification, isolation, and publication rules. Change only repository instructions. Do not modify shared skills, deployed files, or runtime configuration.

## Native execution plan

1. Read repository instructions and confirm public visibility. Create an isolated worktree with repo-start.
2. Add the PR-benefit contract below work-selection guidance in CLAUDE.md. AGENTS.md remains its symlink.
3. Run a bounded description-generation diagnostic with matched baseline, full guidance, each new component removed, and an empty-policy control. Keep private inputs outside this repository. Report limitations rather than claiming general reliability.
4. Inspect the full diff and obtain independent review. Commit the instructions and this spec and plan. Open a PR. Do not merge or provision documentation-only changes.

## Accepted category follow-up

Brian approved the category contract and requested that this existing PR adopt it. Copy the accepted wording without changing its behavior. Verify exact equality with the accepted source, inspect the full branch diff, obtain independent review, and update the PR title and description. The PR itself uses `time-saved` for the expected reduction in review effort. Do not merge or provision documentation-only changes.

The accepted wording already completed a matched excerpt diagnostic outside this repository. Its three unique conditions were the previous benefit guidance, the category contract added, and an empty-policy control. Removing the category contract gives the baseline exactly, so it also served as the leave-one-component-out ablation. All three trials completed once with the same model and historical drafting task. The full candidate selected one allowed primary category and explained a concrete risk. The baseline provided a concrete benefit without a category. Reported total tokens were 3857 for the baseline, 5912 for the full candidate, and 4050 for the empty control. The full candidate used 2055 more total tokens and 39 fewer output tokens than baseline. These harness totals include turn and output-file handling, not isolated policy-token costs.

This update reuses that evidence for identical wording. It does not claim a new NMB-specific trial, a full production workflow test, or measured time savings. The other primary categories, additional-label behavior, and no-fit branch remain unverified. Keep those safeguards. Keep private source inputs outside this public repository.

## Throughput checkpoint

A short repository-local contract is sufficient. Shared-skill rewrites and heading-presence tests would add maintenance without demonstrating a user benefit.
