---
name: personal:resume-codex-session
description: >
  Resume a Codex CLI session in Claude Code.
  Load the session file and continue the work.
---

# Resume a Codex Session

Read the Codex CLI session file and continue that work in this Claude Code session.

## Start

1. If a session file path or index was provided, load it now.
2. If not, list recent sessions and wait for the user to choose one.

## Find

List recent Codex sessions:

```bash
list-codex-sessions
```

Use the output to select by index. It shows:
- Index
- Timestamp
- Project name
- Last-message preview

Ask which session to resume.

To get the file path for a selected session (needed for the transcript load):
```bash
list-codex-sessions --json | jq -r '.[] | select(.index == INDEX) | .file'
```

## Load

After selection, load the full transcript:

```bash
read-codex-session <session-file> --transcript
```

This returns the full conversation for resumption:
- Session metadata (ID, directory, git branch, commit)
- All user messages in order
- All assistant responses
- All tool calls made

Read the whole transcript. Internalize it.

## Confirm

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

## Continue

After user confirmation:

1. Verify current state. Check relevant files still exist and match expectations.
2. Continue where Codex left off. Pick up the task naturally.
3. Apply session context. Reuse patterns, decisions, and constraints from the transcript.

## Rules

1. Always use `--transcript`.
2. Verify state. Files may have changed since the session ended.
3. Acknowledge tool differences. Claude Code may have different capabilities than Codex.
4. Preserve intent. Continue the work in the spirit of what was being done.
5. Do not repeat work. If it was already done, do not redo it.

## Quick Ref

```bash
# List recent sessions (last 10 by default)
list-codex-sessions

# List more sessions or filter by time
list-codex-sessions --limit 20 --days 30

# Get JSON with file paths for programmatic access
list-codex-sessions --json

# Load full transcript for a session
read-codex-session <session-file> --transcript
```
