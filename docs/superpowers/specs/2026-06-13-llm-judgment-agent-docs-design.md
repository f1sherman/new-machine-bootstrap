# LLM Judgment Agent Docs Design

## Goal

Add one concise rule to the managed base Claude/Codex instructions so agents avoid brittle keyword or regex heuristics when the task requires fuzzy human judgment.

## Scope

In scope:

- Update the managed base instruction fragment at `roles/common/files/claude/CLAUDE.md.d/00-base.md`.
- Keep the guidance short and general.
- Rely on existing provisioning, which assembles `~/.claude/CLAUDE.md` from fragments and symlinks `~/.codex/AGENTS.md` to it.

Out of scope:

- Editing deployed files in `~`.
- Adding new scripts, hooks, tools, or Ansible tasks.
- Adding a long examples list.

## Design

Add one bullet near the existing script, parsing, and error-handling guidance:

> Fuzzy judgment: when logic needs semantic or human judgment, use an LLM/model call instead of keyword or regex heuristics.

This placement keeps the rule close to adjacent guidance about scripts and deterministic parsing, where agents are likely to make this mistake.

## Data Flow

Provisioning already installs `roles/common/files/claude/CLAUDE.md.d/00-base.md` to `~/.claude/CLAUDE.md.d/00-base.md`, assembles `~/.claude/CLAUDE.md`, and links `~/.codex/AGENTS.md` to that assembled file. The new rule uses that existing path.

## Error Handling

No runtime behavior changes. If provisioning fails, existing Ansible error handling applies.

## Testing

Verify:

- The managed base fragment contains the new concise rule.
- `roles/common/tasks/main.yml` still installs the fragment, assembles `~/.claude/CLAUDE.md`, and links `~/.codex/AGENTS.md` to it.
