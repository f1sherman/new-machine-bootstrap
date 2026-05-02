# Spec-First Skill Design

## Goal

Add managed shared skills for users who want design discipline but do not want the agent to ask clarifying questions. `_spec-first` should turn a rough request into a written design spec by making reasonable assumptions, documenting those assumptions, and stopping at the written-spec approval gate before implementation planning. `_spec-to-pr` should continue through spec self-approval, plan self-approval, automatic execution, verification, and pull request creation.

## Non-Goals

- Do not modify upstream skill checkouts in `~/.codex/superpowers`.
- Do not change the pinned `obra/superpowers` version.
- Do not add runtime-specific Claude or Codex variants unless shared wording is insufficient.
- Do not weaken the Superpowers hard gate against any implementation action before spec approval.
- Do not let `_spec-to-pr` begin implementation before the spec and plan are complete, self-reviewed, and self-approved.

## Assumptions

- This repository is the source of truth for Brian's managed skills.
- Shared skills belong under `roles/common/files/config/skills/common/` and are copied into both `~/.claude/skills/` and `~/.codex/skills/`.
- The managed skills should use the repository's underscore naming convention: `_spec-first` and `_spec-to-pr`.
- A standalone skill is safer than relying on another named skill, because future agents using `_spec-first` may not know any external process it references.
- A read-only reviewer subagent can improve the silent question and approval pass when the runtime supports subagents, but the main agent must own the final spec.
- `_spec-to-pr` should skip the execution-choice question by selecting subagent-driven execution automatically when available, with inline execution as the fallback.

## Approaches

Recommended: create `roles/common/files/config/skills/common/_spec-first/SKILL.md` and `roles/common/files/config/skills/common/_spec-to-pr/SKILL.md`. Both inline the design process: context exploration, scope assessment, a silent question pass, alternatives, internal design approval, design-quality guidance, spec writing, and self-review. `_spec-first` asks the user to review the written spec before planning. `_spec-to-pr` self-approves the spec and plan, chooses subagent-driven execution automatically when available, verifies the implementation, and invokes the shared pull-request workflow.

Alternative: modify the upstream Superpowers checkout. That works only on the current machine and gets lost on future provisioning, so it is not source controlled by this repo.

Alternative: add Claude-specific and Codex-specific variants. That adds duplication without a runtime-specific need.

## Design

The `_spec-first` shared skill will:

- Trigger when the user asks to skip questions, make assumptions, or just deliver a Superpowers-style spec.
- Be self-contained; do not require the agent to know another named design skill.
- Preserve the no-implementation hard gate, including "or take any implementation action" coverage.
- Require local context exploration before writing.
- Require scope assessment and decomposition for oversized requests.
- Run a silent question pass and answer likely clarifying questions internally.
- Use one read-only reviewer subagent for the silent question and approval pass when subagents are available.
- Skip non-blocking clarifying questions.
- Document assumptions in the spec.
- Include alternatives and a recommended approach.
- Run internal design-section approvals before producing the written spec.
- Include design guidance for isolated components, existing-codebase fit, and targeted refactoring.
- Save the spec to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` unless the user specifies another location.
- Self-review the spec for unfinished markers, contradictions, ambiguity, and scope drift.
- Always check whether `docs/superpowers` is ignored before committing the design spec; when it is ignored, keep the spec local.
- Ask the user to review the written spec before invoking `writing-plans`.

The `_spec-to-pr` shared skill will use the same design workflow, but after self-review it will:

- Skip user spec approval.
- Self-approve the written spec only when assumptions, scope, approach, and verification are coherent.
- Invoke `writing-plans` immediately.
- Skip the execution-choice prompt from `writing-plans`.
- Self-approve the implementation plan only when it covers the spec, uses concrete TDD steps, and defines verification.
- Choose `subagent-driven-development` automatically when subagents are available, or `executing-plans` when they are not.
- Run verification, commit completed work, and invoke `_pull-request` only after the branch is clean.

No Ansible task changes are needed because existing common-skill install tasks already copy `roles/common/files/config/skills/common/` to both agent skill directories.

## Error Handling

If the agent lacks enough context to proceed safely, it may ask one blocking question. Blocking means that proceeding would be destructive, insecure, legally sensitive, financially sensitive, or likely to choose between incompatible architectures.

If the request is too broad, the agent decomposes it and writes a spec only for the first coherent slice.

If the user requests changes after reviewing the spec, the agent updates the spec and repeats self-review.

## Verification

Verify that:

- `roles/common/files/config/skills/common/_spec-first/SKILL.md` exists.
- `roles/common/files/config/skills/common/_spec-to-pr/SKILL.md` exists.
- No runtime-specific `_spec-first` override exists under `roles/common/files/config/skills/claude/` or `roles/common/files/config/skills/codex/`.
- No runtime-specific `_spec-to-pr` override exists under `roles/common/files/config/skills/claude/` or `roles/common/files/config/skills/codex/`.
- The skill has canonical frontmatter and skip-question wording.
- The skill does not reference another named design skill for its core process.
- The skill preserves the implementation gate, including "or take any implementation action", and the `writing-plans` transition.
- The skill includes the anti-pattern warning, isolation guidance, existing-codebase guidance, and spec self-review details inline.
- The skill always checks ignored `docs/superpowers` paths before committing the spec for review.
- `_spec-to-pr` skips user spec review, self-approves the spec and plan, skips the execution-choice prompt, chooses subagent execution automatically when available, and invokes `_pull-request` after verification passes.
- Existing common-skill installation tasks still target both Claude and Codex.
- The repository's targeted skill regression tests pass.
