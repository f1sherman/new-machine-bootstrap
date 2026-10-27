# Repository-local value-first guidance

Status: self-approved for Native execution. Revised after Brian narrowed scope.

## Goal and scope

Require concrete benefit to Brian when selecting work in this personal-only
repository. Other projects may serve different users and priorities. This rule
must not become shared guidance for every checkout.

## Approach

Move the three value/action/safety bullets from the proposed managed Pi and
Claude/Codex base fragments into this repository's `CLAUDE.md`. `AGENTS.md` is
already its symlink. Keep the rule text unchanged. Add a short scope sentence:
the rule applies here because this is Brian's personal-only repository.

Alternatives: a global condition needs ownership inference; a shared opt-in
mechanism adds unnecessary infrastructure. Repository instructions give explicit
scope with no detection logic or runtime changes.

## Boundaries and verification

Restore both managed base fragments exactly to their pre-PR contents. Preserve
all unrelated instructions. No deployed files, services, or authorization gates
change. No provision run is needed for repository Markdown.

Run matched repository-context baseline and leave-one-bullet-out diagnostics,
reusing the previous cases and frozen rubric. Record tokens and limits. Verify
the final diff has no managed fragment changes and the existing symlink exposes
the new section. Obtain independent review and update PR #719. Merge remains
Brian's decision. No rule is added to other repositories by ownership inference.
