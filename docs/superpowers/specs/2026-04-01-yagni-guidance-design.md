# Global YAGNI Guidance Design

## Goal

Add concise YAGNI guidance to the global instruction files managed by this repository.

## Design

Add this exact bullet to both managed base fragments:

> * Follow the YAGNI principle.

The affected deployed files are `~/.pi/agent/AGENTS.md` and
`~/.claude/CLAUDE.md`. Existing assembly and provisioning behavior stays the
same.

## Verification

Run provisioning from the feature worktree. Confirm that both deployed files
contain the exact guidance. Run provisioning in check mode and confirm that it
reports no remaining changes.

No automated test is needed. Such a test would only assert static prose and
would not provide material behavioral protection.
