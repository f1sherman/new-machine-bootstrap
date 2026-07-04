# Agent Skill Cleanup Design

## Goal

Reduce the set of repository-managed skills and skill templates deployed to local agents by reviewing each logical skill and deleting old or unused ones.

## Scope

Review every skill, reference, and template that this repository deploys to agent skill directories, including:

- Common skills copied to `~/.claude/skills` and `~/.codex/skills`
- Claude-specific skills copied to `~/.claude/skills`
- Codex-specific skills copied to `~/.codex/skills`
- Pi skills copied to `~/.pi/agent/skills`
- Personal/domain skills in the managed skills tree

Superpowers skills installed from upstream plugin sources are out of scope unless this repository directly owns the deployed file or link.

## Review Process

Review by logical skill rather than by every mirrored agent variant. For each skill, show:

- Logical skill name
- Installed variants and target agents
- Source file paths in this repository
- Short purpose summary
- Notable helper scripts or permissions

The user decides one of:

- Keep
- Delete
- Unsure / defer

Review in batches of roughly five to seven logical skills to keep decisions manageable.

## Implementation Approach

After decisions are made, remove deleted skills from the repository-managed source tree. If deleting a skill that was previously deployed, add explicit Ansible cleanup tasks for known managed deployed paths so `bin/provision` removes stale copies from `~`.

Avoid compatibility heuristics. Use explicit removal tasks for known managed state.

## Verification

After edits:

- Run repository tests relevant to skill installation and agent configuration.
- Run `bin/provision --check` if the environment allows.
- Inspect `git diff` for accidental unrelated changes.
