---
name: z-resume-claude-session
description: >
  Resume a Claude Code session in Pi by reading the Claude session transcript
  and continuing the work with Pi's tools.
---

# Resume a Claude Code Session in Pi

You are tasked with reading a Claude Code session file and resuming that work in this Pi session.

## Initial Response

1. **If a session file path or index was provided**: read and load that session immediately.
2. **If no path was provided**: list recent Claude sessions for the user to choose from.

## Process

### Step 1: Find and Select a Claude Code Session

If no session was specified, list recent sessions:

```bash
list-claude-sessions
```

This shows recent sessions with an index, timestamp, project name, and preview of the last message.

Ask which session to resume by number. To get the file path for a selected session:

```bash
list-claude-sessions --json | jq -r '.[] | select(.index == INDEX) | .file'
```

### Step 2: Load the Full Session Transcript

Once a session is selected, load the full transcript:

```bash
read-claude-session <session-file> --transcript
```

Read and internalize the complete transcript. This is the context for what was being worked on.

### Step 3: Analyze and Confirm

After loading the transcript, present a brief summary:

```markdown
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

1. Verify current state: check that relevant files still exist and match expected state.
2. Continue naturally using Pi's available tools and skills.
3. Preserve intent, decisions, and constraints from the Claude session.
4. Do not repeat completed work unless verification shows it is missing or stale.

## Guidelines

- Always load the full transcript with `--transcript`.
- Verify state because files may have changed since the Claude session ended.
- Acknowledge tool differences when they matter.
- Preserve the user's original intent.
- Use Pi-native skills and helpers for new work, not Claude-specific workflows, unless interacting with Claude is the point of the task.

## Quick Reference

```bash
list-claude-sessions
list-claude-sessions --limit 20 --days 30
list-claude-sessions --json
read-claude-session <session-file> --transcript
read-claude-session <session-file>
```
