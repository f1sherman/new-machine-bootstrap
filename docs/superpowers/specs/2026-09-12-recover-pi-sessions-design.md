# Recover Pi Sessions Design

## Problem

`_recover-agent-sessions` searches recent Claude and Codex sessions only. A Pi
session can exist on disk and still be absent from Pi's native session list when
a launcher used a nested custom session directory. The recovery helper then
reports no session even though the exact JSONL file is recoverable.

## Requirements

- Include Pi sessions in the same time-window, sorting, summary, and output
  pipeline as Claude and Codex sessions.
- Search Pi session storage recursively so legacy custom directories are found.
- Validate the Pi session header and use its exact ID and cwd.
- Resume Pi by exact JSONL path. Do not depend on native ID discovery.
- Do not depend on HNP, Herdr, or ASR. This helper is generic.
- Ignore unreadable files, malformed JSONL files, symlink aliases, and files
  outside the requested modification-time window.
- Update both installed skill descriptions to include Pi.

## Options

### 1. Read Pi JSONL files directly

Recursively enumerate `~/.pi/agent/sessions`, filter by modification time, read
the authoritative session header, and extract bounded transcript signals using
the existing summary pipeline. This supports both standard and custom layouts.

### 2. Use Pi's SessionManager API

This repeats the native non-recursive discovery limitation that caused the
session to be missed.

### 3. Query ASR

ASR can recover registered HNP sessions, but it is optional and does not cover
all Pi sessions. It would also couple a generic bootstrap helper to HNP runtime
infrastructure.

## Decision

Use option 1. Add a Pi JSONL reader and recursive session enumerator. Reuse the
existing entry hydration and rendering logic. Generate this resume command:

```text
cd "<cwd>" && pi --session "<exact-jsonl-path>"
```

The exact file path works for nested legacy sessions and normal Pi sessions.
Use the most recent `session_info.name` as the preview when present. Collect Pi
user, assistant, and shell-command content in the existing read-data shape so
summary inference remains tool-neutral.

## Verification

Use a temporary HOME with standard and nested Pi fixtures, malformed data, and
an out-of-window file. Disable model summarization with an unavailable Codex
binary. Run the production helper and verify that both valid Pi layouts appear,
invalid data does not appear, ordering is newest first, and each resume command
contains the exact path. Then run the helper against the deployed session store
and confirm it finds the previously missing OpenClaw session.
