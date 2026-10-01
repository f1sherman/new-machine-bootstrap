# Native execution default

Status: self-approved.

## Goal
Reduce token use by executing Superpowers plans inline with `executing-plans` by default.

## Scope and assumptions
Update the common and Pi Quick PR skills and the Claude and Pi base guidance. Preserve approval, authorization, isolation, verification, and PR gates. Explicit user requests for subagent-driven execution still apply. One final fresh-context branch review remains required when authorized and available. No upstream fork, historical-plan rewrite, or new automated policy test.

## Approach
Use personal guidance to select Native execution before the upstream handoff. Quick PR performs its silent design pass inline and selects `executing-plans`, even when subagents are available. Subagent availability alone does not select the more expensive mode.

Alternatives: patch upstream skills (creates maintenance drift); retain automatic subagent selection (does not meet the token goal). Personal guidance is the smallest durable change.

## Verification and rollout
Inspect all active execution-selection guidance, compare both skill copies, validate frontmatter, and review the full branch. Record scenario walkthroughs as manual checks, not model behavior evaluations or measured token savings. No low-value literal policy test. The HNP source already pins Superpowers v6.4.1, which contains PR 2318; the local installed checkout is older. Deployment needs the managed provisioning path after merge. Do not edit deployed files directly.

## Checklist
- [x] Explore context, silent question pass, compare approaches, self-review and self-approve spec.
- [x] Commit spec, write and self-approve plan.
- [x] Update guidance and verify consistency and authorization boundaries.

PR creation and monitoring follow the committed implementation.
