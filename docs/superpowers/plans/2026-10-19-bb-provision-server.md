# One-time bb server selection implementation plan

> Execution: Native, using superpowers:executing-plans. Self-reviewed and approved.

**Goal:** Save an explicit server choice once, with personal/work instructions.
**Architecture:** A local Ansible action plugin owns the controller-side prompt
and atomic JSON state. The existing bb command block consumes the action's
result and scopes the selected URL to bb commands.
**Tech stack:** Python standard library, Ansible, unittest, pseudo-terminals.
**Spec:** `docs/superpowers/specs/2026-10-19-bb-provision-server-design.md`

## Constraints and review focus

Never guess personal/work classification or import the obsolete `use` setting.
Blank is a saved work choice and must survive noninteractive repeat runs.
Noninteractive first run and interrupted input must never save a blank choice.
A saved personal URL overrides stale CLI connection settings automatically.
Check mode and unenrolled machines must never prompt or save configuration.

## Task 1: Helper, integration, and verification

Files:
- Create `action_plugins/configure_bb_server.py` and
  `tests/configure-bb-server.py`.
- Modify `roles/macos/tasks/install_bb.yml`, `README.md`, and
  `.github/workflows/integration-test.yml`.

Interface: action takes `path`, returns `server_url` (HTTP(S) string or null)
and `changed` (boolean). Errors fail the task with instructions.
Config schema: JSON object containing `server_url`; private atomic write.

- [x] Add behavioral tests for PTY personal/work/custom/invalid/EOF choices,
  saved-state replay, validation, no-terminal first run, and file permissions.
  Run `python3 tests/configure-bb-server.py`: observed red before action exists.
- [x] Implement the action and CI invocation; rerun the same tests: green.
- [x] Invoke the action for enrolled Macs only, outside check mode.
  Replace per-run variable logic with the saved result.
- [x] Update README with one-time prompt and saved config details.
- [x] Run macOS `env -u BB_SERVER_URL bin/provision --tags bb` through a PTY;
  answer `1` on this personal Mac. Expect failed=0 and one configuration change.
- [x] Repeat without a terminal or flags: failed=0, changed=0, no prompt.
- [x] Run check mode and temporary-config work/null integration verification.
- [x] Verify diff, commit, and obtain fresh branch review.

Publication is tracked by PR #688.

## Execution record

Existing linked worktree is isolated and clean at implementation start.
User approved the design and prompt wording. PR state must be refreshed before
publication; review or auto-merge state does not grant merge authority.
Pre-flight: single task; action result shape matches Ansible's consumer.

Ruling: command modules lose their controlling terminal, so use a native
Ansible action instead of a subprocess helper. A first integration probe proved
that piped stdout buffered the prompt. Printing the prompt to stderr fixes the
production pipeline; PTY tests now use the same pipeline. No dependency patch.

Verification: 10 behavioral tests passed. Live personal selection completed
(ok=14, changed=1, failed=0), and a noninteractive repeat with inherited URL
removed completed (ok=14, changed=0, failed=0) without prompting. Check mode:
ok=9, changed=0, failed=0. A temporary-fixture run of the production task file
executed all four bb commands, including both install branches, in each case:
work/null with no environment URL; work/null preserving an inherited work URL;
and personal overriding a stale inherited URL. No real work server was used.
Full untagged provisioning was not run; the affected bb workflow was verified.
Final independent review found no actionable defects; no findings remain open.
