# Subagent Commit Skill

## Problem

When the commit skill runs inline, it loads `git status`, `git diff`, and commit planning logic into the main conversation's context window. This context is ephemeral and not useful after the commit completes, but it permanently consumes space in the main context.

## Solution

Run the commit logic in a foreground subagent. The main agent summarizes what was done, dispatches the subagent, and gets back a short result. All git diff/status/planning context is isolated in the subagent's window and discarded after.

## Design

### Commit Skill (thin dispatcher)

**File:** `roles/common/files/config/skills/common/committing-changes/SKILL.md`
**Deployed to:** `~/.claude/skills/committing-changes/SKILL.md`

The skill is rewritten to ~5 lines of instruction:

1. Write a 2-4 sentence summary of what was accomplished in this session
2. Dispatch `personal:committer` as a foreground Agent with the summary as the prompt
3. Report the agent's result to the user

The skill frontmatter preserves `name: commit` and the description stating that invoking the skill is explicit approval to commit and push.

### Committer Agent (does the work)

**File:** `roles/common/templates/dotfiles/claude/agents/personal:committer.md`
**Deployed to:** `~/.claude/agents/personal:committer.md`

The agent receives a short summary from the main agent and handles everything else:

**Input:** A 2-4 sentence summary of what was done and why.

**Steps:**
1. Run `git status` to see all changes
2. Run `git diff` to read the actual modifications
3. Decide whether to make one or multiple commits based on the diff and the summary context
4. Group files into logical commits
5. Write commit messages in imperative mood, informed by the summary
6. Call `~/.claude/skills/committing-changes/commit.sh -m "message" file1 file2 ...` for each commit
7. Run `git push`
8. Return `git log --oneline -n <count>` as the result

**Agent configuration:**
- **Tools:** Bash, Read
- **Model:** sonnet

### commit.sh

No changes. The agent calls it identically to how the skill calls it today.

### Ansible Deployment

No new Ansible tasks needed. The existing `with_filetree` template task in `roles/common/tasks/main.yml` recursively copies everything under `roles/common/templates/dotfiles/` to the home directory. Adding a new file to `roles/common/templates/dotfiles/claude/agents/` will be deployed automatically. The skill file is already copied by the existing skill installation tasks.

## Interaction Flow

```
User: /commit
  |
  v
Skill loads into main context (~5 lines)
  |
  v
Main agent writes 2-4 sentence summary
  |
  v
Main agent dispatches Agent(subagent_type="personal:committer", prompt=summary)
  |  -- foreground, blocks until complete --
  |
  v (in subagent context, isolated)
personal:committer runs git status, git diff
Plans commits, calls commit.sh, pushes
Returns git log output
  |
  v (back in main context)
Main agent receives short result, reports to user
```

## Context Budget

**Main context consumption:**
- Skill text: ~5 lines
- Summary written by main agent: ~100 tokens
- Agent result: ~5-10 lines of git log

**Subagent context (isolated, discarded):**
- Full git diff, git status, commit planning, commit.sh output

## Files Changed

1. `roles/common/files/config/skills/common/committing-changes/SKILL.md` — rewrite to thin dispatcher
2. `roles/common/templates/dotfiles/claude/agents/personal:committer.md` — new agent definition
