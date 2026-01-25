---
name: personal:resume-claude-session
description: >
  Resume a Claude Code session within Codex by reading the Claude session file and continuing the work.
  Use when the user wants to continue Claude work in Codex.
---

# Resume a Claude Code Session in Codex

You are tasked with reading a Claude Code session file and resuming that work within this Codex session.

## Initial Response

1. **If a session file path or index was provided**: Read and load that session immediately.

2. **If no path was provided**: List recent sessions for the user to choose from.

## Process

### Step 1: Find and Select a Claude Code Session

If no session was specified, list recent sessions:

```bash
list-claude-sessions
```

This shows the 10 most recent sessions with:
- Index number (for easy selection)
- Timestamp
- Project name
- Preview of the last message

Present this to the user and ask which session to resume (by number).

To get the file path for a selected session (needed for step 2):
```bash
list-claude-sessions --json | jq -r '.[] | select(.index == INDEX) | .file'
```

To filter by project:
```bash
list-claude-sessions --project <project-dir>
```

### Step 2: Load the Full Session Transcript

Once a session is selected, load the full transcript into context:

```bash
read-claude-session <session-file> --transcript
```

This outputs the complete conversation in a format optimized for resumption:
- Session metadata (ID, directory, git branch, Claude Code version)
- All user messages in order
- All assistant responses
- All tool calls made

**Read and internalize this entire transcript.** This is your context for what was being worked on.

### Step 3: Analyze and Confirm

After loading the transcript, present a brief summary:

```
I've loaded the Claude Code session from [timestamp].

**Working Directory**: [cwd]
**Git Branch**: [branch]

**What was being worked on**:
- [Summary from user messages and context]

**Where we left off**:
- [Last significant action or state]

**Recommended next step**:
- [Most logical continuation]

Ready to continue?
```

### Step 4: Continue the Work

After user confirmation:

1. **Verify current state**: Check that relevant files still exist and match expected state
2. **Pick up where Claude left off**: Continue the task naturally
3. **Apply learnings**: Use any patterns, decisions, or context from the session

## Guidelines

1. **Load the full transcript**: Always use `--transcript` to get complete context
2. **Verify state**: Files may have changed since the session ended
3. **Acknowledge tool differences**: Codex may have different capabilities than Claude Code
4. **Preserve intent**: Continue the work in the spirit of what was being accomplished
5. **Don't repeat work**: If something was already done in the session, don't redo it

## Quick Reference

```bash
# List recent sessions (shows last 10 by default)
list-claude-sessions

# List more sessions or filter by time/project
list-claude-sessions --limit 20 --days 30
list-claude-sessions --project <project-name>

# Get JSON with file paths for programmatic access
list-claude-sessions --json

# Load full transcript for a session
read-claude-session <session-file> --transcript

# Get summary only (less detail)
read-claude-session <session-file>
```
