---
name: personal:resume-codex-session
description: >
  Resume a Codex CLI session within Claude Code by reading the Codex session file and continuing the work.
  Use when the user wants to continue Codex work in Claude.
---

# Resume a Codex Session in Claude Code

You are tasked with reading a Codex CLI session file and resuming that work within this Claude Code session.

## Initial Response

1. **If a session file path or index was provided**: Read and load that session immediately.

2. **If no path was provided**: List recent sessions for the user to choose from.

## Process

### Step 1: Find and Select a Codex Session

If no session was specified, list recent sessions:

```bash
list-codex-sessions
```

This shows the 10 most recent sessions with:
- Index number (for easy selection)
- Timestamp
- Project name
- Preview of the last message

Present this to the user and ask which session to resume (by number).

To get the file path for a selected session (needed for step 2):
```bash
list-codex-sessions --json | jq -r '.[] | select(.index == INDEX) | .file'
```

### Step 2: Load the Full Session Transcript

Once a session is selected, load the full transcript into context:

```bash
read-codex-session <session-file> --transcript
```

This outputs the complete conversation in a format optimized for resumption:
- Session metadata (ID, directory, git branch, commit)
- All user messages in order
- All assistant responses
- All tool calls made

**Read and internalize this entire transcript.** This is your context for what was being worked on.

### Step 3: Analyze and Confirm

After loading the transcript, present a brief summary:

```
I've loaded the Codex session from [timestamp].

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
2. **Pick up where Codex left off**: Continue the task naturally
3. **Apply learnings**: Use any patterns, decisions, or context from the session

## Guidelines

1. **Load the full transcript**: Always use `--transcript` to get complete context
2. **Verify state**: Files may have changed since the session ended
3. **Acknowledge tool differences**: Claude Code may have different capabilities than Codex
4. **Preserve intent**: Continue the work in the spirit of what was being accomplished
5. **Don't repeat work**: If something was already done in the session, don't redo it

## Quick Reference

```bash
# List recent sessions (shows last 10 by default)
list-codex-sessions

# List more sessions or filter by time
list-codex-sessions --limit 20 --days 30

# Get JSON with file paths for programmatic access
list-codex-sessions --json

# Load full transcript for a session
read-codex-session <session-file> --transcript

# Get summary only (less detail)
read-codex-session <session-file>
```
