---
name: _commit
description: Create git commits with no AI attribution. Use when creating git commits in the current repository.
---

# Commit Changes

## Process

1. Inspect `git status --short`, `git diff --stat`, `git diff`, and `git diff --cached` when staged changes exist.
2. Decide whether to create one commit or multiple atomic commits. Keep each commit coherent and leave the repository in a working state after each commit.
3. Write imperative commit messages that explain why the change exists.
4. Run:
   ```bash
   bash ~/.local/share/skills/_commit/commit.sh -m "Commit message" file1 file2
   ```
5. If `commit.sh` refuses an ignored file, do not bypass it. Pick non-ignored task files or stop and report the ignored path.
6. If there are no changes to commit, report `No changes to commit.`

## Important

- Never add AI attribution, `Generated with Codex`, or `Co-Authored-By` lines.
- Commit only files that belong to the current task.
- Pass explicit files, not `.` or the repository root.
- Never bypass `.gitignore`.
- Do not push.
