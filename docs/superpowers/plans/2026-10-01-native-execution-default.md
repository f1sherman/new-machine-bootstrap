# Native execution default implementation plan

> Use `superpowers:executing-plans` to implement this plan inline. Status: self-approved.

**Goal:** Reduce per-task agent context costs while preserving final review and verification.
**Spec:** `docs/superpowers/specs/2026-10-01-native-execution-design.md`
**Architecture:** Select the upstream Native mode through managed personal guidance; keep upstream files unchanged.

## Global constraints
Preserve authorization, approval, isolation, verification and PR gates. Honor explicit execution-mode requests. No automated prose-enforcement tests. No direct deployed-file changes.

### Task 1: Change active guidance
**Files:** common `_quick-pr/SKILL.md`, Pi `z-quick-pr/SKILL.md`, Claude `CLAUDE.md.d/00-base.md`, Pi `AGENTS.md.d/00-base.md`, all under `roles/common/files/`.
**Interfaces:** No shared code interfaces; both Quick PR copies must select the same mode.
- [x] Replace the automatic subagent execution rule in both Quick PR copies with Native execution by default and explicit-user opt-in for subagent-driven development.
- [x] Replace the design-reviewer dispatch in both skills with an inline silent question pass.
- [x] Add the Native default to both harness base guides; replace Claude's existing unconditional subagent rule while preserving its spec approval rule.
- [x] Keep one final fresh-context branch review at the PR workflow gate instead of adding a duplicate review.
- [x] Validate YAML frontmatter with `yq`, compare skill bodies with `diff`, inspect the complete diff and active guidance references. Expected: valid frontmatter, matching execution rules, no unconditional subagent default.
- [x] Walk through ordinary execution with subagents present, explicit subagent opt-in, and unavailable delegation. Expected: Native, explicit chosen mode, and honest review limitation respectively. These are manual walkthroughs, not model evals.

After committing, run the existing PR review workflow, fix material findings, create PR and arm monitoring.

## Evidence limits
No measured token reduction and no causal agent-behavior evaluation are claimed. Managed deployment remains pending merge. Installed upstream skills must be updated through HNP provisioning to the already configured v6.4.1 before the new Native workflow can run end to end locally.
