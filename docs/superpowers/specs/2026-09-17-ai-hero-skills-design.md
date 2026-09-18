# AI Hero Skills Adoption Design

**Status:** Approved

## Goal

Install the selected Matt Pocock skills for Claude Code, Codex, and Pi. Keep the
installed copies reviewable and synchronized with tagged upstream releases.
Record why every published skill was installed or skipped and preserve useful
ideas from skipped skills.

## Non-goals

- Adopt Matt's full idea-to-ship workflow.
- Add issue-tracker configuration to every repository.
- Let the deep-interview skills activate during ordinary engineering work.
- Replace the existing specification, implementation, review, TDD, research, or
  pull-request workflows.
- Solve post-merge effect confirmation in this change.

## Assumptions

- The upstream source is `mattpocock/skills` under the MIT license.
- Tagged releases are the update boundary. The initial version is `v1.2.3`.
- A skill update must produce a repository diff before it reaches a machine.
- Original upstream skill names should remain stable across all three harnesses.
- Pi and Claude honor `disable-model-invocation: true`. Codex honors
  `policy.allow_implicit_invocation: false` in `agents/openai.yaml`.

## Selected skills

Install these upstream skills:

- `grill-with-docs`
- `grilling`
- `domain-modeling`
- `resolving-merge-conflicts`
- `wait-what`
- `writing-for-agents`

The complete 25-skill decision ledger and usage guide lives in
`docs/ai-hero-skills-guide.md`.

## Local adaptations

Keep the upstream content unchanged except for these explicit patches:

1. Enforce `disable-model-invocation: true` in all three deep-design skill
   frontmatter files. Also enforce `policy.allow_implicit_invocation: false` in
   all three `agents/openai.yaml` files. The three skills form an explicit,
   user-invoked deep-design bundle in Claude, Codex, and Pi.
2. In `resolving-merge-conflicts`, replace the absolute instruction to always
   resolve and never abort. The local instruction must continue a clearly
   intended operation, never abort merely because resolution is difficult, and
   stop for a human decision when available context cannot establish whether
   the operation itself should continue.

Do not rename selected skills per harness. Their upstream names keep internal
references valid and make update diffs easier to review. The updater must parse
invocation metadata structurally enough to enforce these invariants on every
release. It must abort when the merge-conflict patch preimage is missing or
ambiguous rather than silently generating a partially adapted tree.

## Source and installation architecture

Vendor one generated source tree at
`roles/common/files/vendor/mattpocock-skills/`. Each selected skill keeps its
complete upstream directory, supporting files, and agent metadata. Each skill
also contains:

- `LICENSE` with the upstream MIT license.
- `UPSTREAM.md` with repository, tag, commit, and the local patch list.

Add Ansible tasks that copy each selected directory into:

- `~/.claude/skills/<name>/`
- `~/.codex/skills/<name>/`
- `~/.pi/agent/skills/<name>/`

The existing common and harness-specific skill copies remain unchanged. Each
installed skill carries a generated checksum marker. Provisioning compares that
marker before copying. A changed marker causes the destination directory to be
removed and recopied, so files removed upstream cannot survive deployment.
Normal same-version runs remain idempotent. If a selected skill is retired
later, its name must be added to the repository's explicit managed-skill cleanup
list.

## Update workflow

Add `bin/update-ai-hero-skills` as the only supported generator for the vendored
source tree. It must:

1. Read the pinned tag from `vars/tool_versions.yml`.
2. Fetch that exact tag from `mattpocock/skills`, unless a local source checkout
   is supplied for testing.
3. Resolve annotated tags to their commit and reject symlinks in selected source
   trees.
4. Refuse a moved tag when the existing generated metadata records the same tag
   with a different commit, unless the operator supplies an explicit override.
5. Copy only the approved skills and their complete supporting content.
6. Apply the two documented local adaptations with fail-closed preconditions.
7. Add source, license, and generated checksum metadata.
8. Replace the generated vendor tree atomically enough that removed upstream
   files do not survive an update.
9. Support a check mode that reports drift without changing the repository.

Renovate watches the pinned Git tag. A package rule matching only
`mattpocock/skills` runs `bin/update-ai-hero-skills` once after a tag bump, with
bounded file filters for the pin and generated vendor tree. The Renovate pull
request therefore includes both the pin and generated skill diff. The
self-hosted workflow sets an anchored global command allowlist for exactly
`bin/update-ai-hero-skills`. The updater uses Node.js and Git, which are present
in Renovate's execution environment.

## Guide and retained ideas

`docs/ai-hero-skills-guide.md` is the durable decision record. For installed
skills it must explain the trigger and important limits. For skipped skills it
must record the reason and any principle that should improve the current
harness.

This change updates the repository-managed `z-fix` and `z-create-handoff`
variants for Claude, Codex, and Pi:

- `z-fix` adds a difficult-bug diagnosis contract: a named red-capable command,
  minimized reproduction, ranked falsifiable hypotheses, tagged temporary
  instrumentation, secret redaction, and regression tests only at a correct
  behavioral seam.
- `z-create-handoff` requires secret and personal-information redaction and
  references existing artifacts instead of duplicating them.

Larger workflow changes, including review-axis changes and post-merge effect
confirmation, stay as follow-up recommendations in the guide.

## Alternatives considered

### Recommended: generated vendored copies with Renovate refresh

This produces reviewable changes, keeps provisioning deterministic, and makes
local adaptations explicit. It adds one updater and a bounded Renovate command.

### Clone upstream during provisioning

This reduces repository content but adds network dependency and makes behavior
changes less visible at review time. Rejected.

### Git submodule plus overlays

This preserves upstream history but adds submodule lifecycle complexity and
still needs a patch layer. Rejected.

### Manual copies

This is simple initially but has no reliable update path. Rejected.

## Verification

- Unit-test the updater against a local fixture repository. Verify selection,
  complete recursive copying, frontmatter and Codex invocation patches,
  fail-closed merge-conflict patching, metadata, moved-tag protection, rejection
  of symlinks, removal of stale files, and check-mode drift detection.
- Run the updater against upstream `v1.2.3` and run it again in check mode.
- Validate every generated `SKILL.md` with Pi's skill discovery or equivalent
  frontmatter checks.
- Run Ansible syntax check.
- Run provisioning from the feature worktree.
- Confirm selected skills exist in all three deployed directories, deleted
  upstream files do not survive, and the three deep-design skills are user-only
  in Claude, Codex, and Pi.
- Run provisioning check mode to confirm idempotence.

## Rollout and follow-up

Provision from the feature worktree after local verification. The guide retains
a follow-up for a separate, low-friction post-merge confirmation workflow that
distinguishes implementation from confirmed real-world effect.
