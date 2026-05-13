# Global CLAUDE.md: never swallow errors

## Goal
Add telegraph-style guidance to the provisioned global CLAUDE.md so future Claude sessions on this machine never silently swallow errors.

## Change
File: `roles/common/files/claude/CLAUDE.md.d/00-base.md` (this file is concatenated into `~/.claude/CLAUDE.md` during `bin/provision`).

Add one bullet, matching surrounding style:

```
* Errors: never silently swallow in code/scripts. Log at minimum.
```

Placement: alphabetically/semantically near the `Comments:` and `Testing:` bullets, e.g. just before `Verification:` — keeps grouping of "how to write code" rules together.

## Non-goals
- No changes to scripts, hooks, or tooling.
- No edits to the project-level `CLAUDE.md` files (this is global guidance only).
- Not introducing structured error-logging conventions; just establishing the floor (never swallow, always log).

## Rollout
1. Edit `00-base.md`.
2. Run `bin/provision` to re-render `~/.claude/CLAUDE.md`.
3. Verify the bullet appears in the deployed file.
4. Commit and open PR.
