---
name: personal:create-handoff
description: >
  Write concise handoff documents to transfer work context to another agent session.
  Use when the user asks to hand off or wrap up work for later.
---

# Create Handoff

Write a handoff that transfers work to the next session. Keep it tight. Keep the facts. Drop filler.

## Process

### 1. Filepath & Metadata
- Create the file at `.coding-agent/handoffs/ENG-XXXX/YYYY-MM-DD_HH-MM-SS_ENG-ZZZZ_description.md`.
- Create missing directories.
- Use today's date for `YYYY-MM-DD`.
- Use 24-hour time for `HH-MM-SS`.
- Use `ENG-XXXX` for the ticket folder. Use `general` if there is no ticket.
- Use `ENG-ZZZZ` in the filename when a second ticket number exists. Omit it otherwise.
- Use a brief kebab-case description.
- Run `~/.local/bin/spec-metadata` to collect all metadata.
- Examples:
  - With ticket: `2025-01-08_13-55-22_ENG-2166_create-context-compaction.md`
  - Without ticket: `2025-01-08_13-55-22_create-context-compaction.md`

### 2. Handoff writing
Write the handoff using the filepath and metadata from step 1. Use this exact frontmatter shape, then the body below it:

Use the following template structure:
```markdown
---
date: [Current date and time with timezone in ISO format]
git_commit: [Current commit hash]
branch: [Current branch name]
repository: [Repository name]
topic: "[Feature/Task Name] Implementation Strategy"
tags: [implementation, strategy, relevant-component-names]
status: complete
last_updated: [Current date in YYYY-MM-DD format]
type: implementation_strategy
---

# Handoff: ENG-XXXX {very concise description}

## Task(s)
{What you were working on. Include status for each item: completed, in progress, planned, discussed. If this is an implementation plan, name the current phase. Reference the plan and/or research docs you used, if any.}

## Critical References
{List the key specs, decisions, or design docs to follow. Keep it to 2-3 file paths. Leave blank if none.}

## Recent changes
{Recent code changes you made, using `path:line` syntax.}

## Learnings
{Key takeaways: patterns, bug root causes, traps, or other facts the next agent needs. Include file paths when useful.}

## Artifacts
{Exhaustive list of artifacts you created or updated. Use file paths and/or `file:line` references. Include docs, plans, and anything the next agent should read first.}

## Action Items & Next Steps
{Action items for the next agent, based on the current status of each task.}

## Other Notes
{Anything useful that does not fit above: relevant code locations, docs, constraints, or extra context.}
```

### 3. Approve and Sync
Ask the user to review and approve. If they want changes, make them and ask again.

After approval, reply with a short confirmation and the handoff path:

```
Handoff created and synced! You can resume from this handoff in a new session with:

.coding-agent/handoffs/ENG-2166/2025-01-08_13-44-55_ENG-2166_create-context-compaction.md
```

## Additional Notes & Instructions
- Include enough detail to resume work without guesswork.
- Be precise. Cover the goal and the supporting detail.
- Avoid large snippets. Prefer `path/to/file.ext:line` references.
