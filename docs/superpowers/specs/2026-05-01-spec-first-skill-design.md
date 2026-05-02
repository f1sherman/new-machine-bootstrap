# Spec-First Skill Design

## Goal

Add a managed shared skill for users who want Superpowers design discipline but do not want the agent to ask clarifying questions. The skill should turn a rough request into a written design spec by making reasonable assumptions, documenting those assumptions, and stopping at the written-spec approval gate before implementation planning.

## Non-Goals

- Do not modify upstream Superpowers in `~/.codex/superpowers`.
- Do not change the pinned `obra/superpowers` version.
- Do not add runtime-specific Claude or Codex variants unless shared wording is insufficient.
- Do not weaken the Superpowers hard gate against any implementation action before spec approval.

## Assumptions

- This repository is the source of truth for Brian's managed skills.
- Shared skills belong under `roles/common/files/config/skills/common/` and are copied into both `~/.claude/skills/` and `~/.codex/skills/`.
- The managed skill should use the repository's underscore naming convention: `_spec-first`.
- A standalone skill is safer than telling an agent to invoke `superpowers:brainstorming` while skipping questions, because `superpowers:brainstorming` explicitly requires questions.

## Approaches

Recommended: create `roles/common/files/config/skills/common/_spec-first/SKILL.md`. It mirrors the useful parts of brainstorming: context exploration, scope assessment, alternatives, spec writing, self-review, user review, and transition to `writing-plans`. It replaces clarifying questions with assumptions and replaces section approvals with one written-spec approval.

Alternative: modify the upstream Superpowers checkout. That works only on the current machine and gets lost on future provisioning, so it is not source controlled by this repo.

Alternative: add Claude-specific and Codex-specific variants. That adds duplication without a runtime-specific need.

## Design

The new shared skill will:

- Trigger when the user asks to skip questions, make assumptions, or just deliver a Superpowers-style spec.
- Preserve the no-implementation hard gate, including the upstream "or take any implementation action" coverage.
- Require local context exploration before writing.
- Require scope assessment and decomposition for oversized requests.
- Skip non-blocking clarifying questions.
- Document assumptions in the spec.
- Include alternatives and a recommended approach.
- Save the spec to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` unless the user specifies another location.
- Self-review the spec for unfinished markers, contradictions, ambiguity, and scope drift.
- Commit the design spec before asking for user review, unless `docs/superpowers` is ignored by the repository.
- Ask the user to review the written spec before invoking `writing-plans`.

No Ansible task changes are needed because existing common-skill install tasks already copy `roles/common/files/config/skills/common/` to both agent skill directories.

## Error Handling

If the agent lacks enough context to proceed safely, it may ask one blocking question. Blocking means that proceeding would be destructive, insecure, legally sensitive, financially sensitive, or likely to choose between incompatible architectures.

If the request is too broad, the agent decomposes it and writes a spec only for the first coherent slice.

If the user requests changes after reviewing the spec, the agent updates the spec and repeats self-review.

## Verification

Verify that:

- `roles/common/files/config/skills/common/_spec-first/SKILL.md` exists.
- No runtime-specific `_spec-first` override exists under `roles/common/files/config/skills/claude/` or `roles/common/files/config/skills/codex/`.
- The skill has canonical frontmatter and skip-question wording.
- The skill preserves the implementation gate, including "or take any implementation action", and the `writing-plans` transition.
- The skill requires committing the spec before review while respecting ignored `docs/superpowers` paths.
- Existing common-skill installation tasks still target both Claude and Codex.
- The repository's targeted skill regression test passes.
