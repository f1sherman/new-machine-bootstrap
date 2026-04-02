---
name: personal:commit
description: >
  Create git commits with no AI attribution and push.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit and push.
---

# Commit Changes

You are tasked with creating git commits for the changes made during this session. The user has given approval by invoking this skill — proceed without asking for confirmation.

## Process

1. **Think about what changed:**
   - Review the conversation history and understand what was accomplished
   - Run `git status` to see current changes
   - Run `git diff` to understand the modifications
   - Consider whether changes should be one commit or multiple logical commits

2. **Plan your commit(s):**
   - Identify which files belong together
   - Draft clear, descriptive commit messages
   - Use imperative mood in commit messages
   - Focus on why the changes were made, not just what
   - Each commit MUST leave the codebase in a working state (tests/lint passing, etc.)

3. **Commit and push:**
   - Use the `commit.sh` script in this skill directory:
     ```bash
     ~/.claude/skills/committing-changes/commit.sh -m "Your commit message" file1 file2 ...
     ```
   - Or for Codex: `~/.codex/skills/committing-changes/commit.sh`
   - Push to the remote: `git push`
   - Show the result with `git log --oneline -n [number]`

## The commit.sh Script

A helper script is available at `~/.claude/skills/committing-changes/commit.sh` (or `~/.codex/skills/committing-changes/commit.sh` for Codex) that:
- Takes a commit message via `-m "message"`
- Takes a list of files to stage
- Creates the commit without any AI attribution
- Validates inputs and shows the result

**Usage:**
```bash
commit.sh -m "Add user authentication" src/auth.ts src/login.tsx
```

Agents can use this script directly without invoking this skill when user approval has already been obtained or is not required.

## Important
- **NEVER add co-author information or AI attribution**
- Commits should be authored solely by the user
- Do not include any "Generated with [AI]" messages
- Do not add "Co-Authored-By" lines
- Write commit messages as if the user wrote them

## Remember
- You have the full context of what was done in this session
- Group related changes together
- Keep commits focused and atomic when possible
- The user trusts your judgment - they asked you to commit
