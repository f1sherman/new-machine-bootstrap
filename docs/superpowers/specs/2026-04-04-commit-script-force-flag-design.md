# commit.sh --force Flag for Gitignored Files

**Date:** 2026-04-04

## Problem

`commit.sh` uses `git add -- "$file"` to stage files before committing. This fails when a file matches a `.gitignore` pattern — even if the file was already force-added to the index by an earlier step. Git refuses to `git add` files matching gitignore patterns without `--force`, regardless of their current index state.

The original trigger: the brainstorming skill writes specs to `docs/superpowers/specs/`, and `docs/` was gitignored. The `docs/` gitignore entry has since been removed, but the general problem remains for any gitignored path (e.g., `tmp/`, `dist/`, `build/`).

## Design

### New `--force` / `-f` flag

Add a `--force` (`-f`) flag to `commit.sh`. Default behavior (no flag) preserves the current safety: gitignored files cause an error. With `--force`, gitignored files are staged via `git add --force`.

### Modified staging flow

1. **Pre-check:** Before staging anything, run `git check-ignore` on each file (no special flags needed). Collect matches into a gitignored-files list.
2. **Without `--force`:** If any files are gitignored, print them, suggest `--force`, and exit non-zero. Nothing is staged or committed.
3. **With `--force`:** Stage gitignored files with `git add --force`, all others with plain `git add`. Then commit and push as normal.

The entire commit fails if any file can't be staged — no partial commits.

### Files modified

- `~/.claude/skills/committing-changes/commit.sh` — add `--force` flag parsing, pre-check gitignored files, conditional staging logic
- `~/.claude/skills/committing-changes/SKILL.md` — document `--force` flag so Claude knows to retry on gitignore errors

### Error message format

When gitignored files are detected without `--force`:

```
Error: The following files are gitignored and cannot be staged without --force:
  docs/superpowers/specs/some-spec.md

Use --force (-f) to commit these files anyway:
  commit.sh --force -m "message" file1 file2 ...
```

## Testing

- Verify `commit.sh` without `--force` fails for gitignored files with helpful message
- Verify `commit.sh --force` successfully stages and commits gitignored files
- Verify normal (non-gitignored) files still work without `--force`
- Verify mixed gitignored + non-gitignored files fail without `--force` (no partial staging)
