---
date: 2026-06-13
topic: Add non-interactive mode to murder
status: approved
---

# Design: murder non-interactive mode

## Goal

Make the macOS-managed `murder` helper usable from scripts and agent commands without hanging on a confirmation prompt.

## Current State

`roles/macos/templates/murder` accepts a PID, process name, or `:port`, displays process details, asks for confirmation with `STDIN.gets`, then sends `TERM` and falls back to `KILL` if the process does not exit.

The existing `--force` option skips confirmation, but the command has no conventional `--yes` automation flag, and a required prompt with closed stdin can crash instead of producing a clear error.

## Desired Behavior

- `murder --yes <pid|name|:port>` and `murder -y <pid|name|:port>` skip the prompt.
- `murder --force <target>` remains supported as a compatibility alias for prompt bypass.
- Prompt bypass keeps the existing termination behavior: try `TERM`, wait, then use `KILL` only if still alive.
- Without `--yes` or `--force`, the command still prompts in an interactive terminal.
- If confirmation is required but stdin is unavailable or closed, the command exits with a clear error and does not kill the process.

## Approach

Use a small parser change in `roles/macos/templates/murder`: introduce a `skip_confirmation` boolean, wire `--yes` and `--force` to it, and pass it to `terminate_process`.

Tighten `confirm_kill` so it reads one line, handles EOF explicitly, and logs an actionable error. This keeps dangerous default behavior guarded while giving automation an explicit consent flag.

## Testing

Add a Ruby regression test invoked by CI:

- start a temporary child process that exits on `TERM`
- run `murder --yes <pid>` with stdin closed and assert the prompt is not printed
- start another child and run `murder -y <pid>` to cover the short flag
- start another child and run `murder <pid>` with stdin closed, assert it fails clearly, and assert the process remains alive

Also run Ruby syntax validation, CI test inventory, and repo policy checks.
