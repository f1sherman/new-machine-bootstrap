# ChatGPT Sites Working Directory Design

**Status:** Self-approved

## Goal

Make the Codex ChatGPT Sites push exception validate Git state in the working
directory requested by the shell tool call.

## Non-goals

- Do not broaden the allowed command shapes, hosts, refspecs, or authentication
  settings.
- Do not parse `cd`, `git -C`, or other repository-selection syntax from the
  command.
- Do not change the Pi guard, which already receives its selected working
  directory as an explicit argument.

## Evidence and Assumptions

- A captured failing Site publish tool call contains a `workdir` field that
  points to the generated Site repository.
- The Codex hook currently reads only `.tool_input.command` and runs every Git
  subprocess in the hook process directory.
- The same redacted publish command passes when the hook process starts in the
  Site repository and fails when it starts in the parent directory.
- Codex passes the shell tool's requested directory as `.tool_input.workdir` in
  the `PreToolUse` payload.

## Recommended Approach

Read `.tool_input.workdir` with the command. Pass that directory to every Git
subprocess used by the strict Sites exception. Keep the normal push-blocking
analysis unchanged so this fix only affects the existing exception.

Require a nonempty working directory for the exception. If it is missing,
invalid, or not a Git repository, keep the fail-closed denial. This uses one
explicit protocol field and avoids path inference.

## Alternatives Considered

### Continue to use the hook process directory

This preserves current code but does not represent the shell tool request. It
causes the reported false denial.

### Parse repository changes from the command

Parsing `cd`, `git -C`, wrappers, and shell state would broaden a deliberately
strict security boundary. It is unnecessary because the tool call already has
an explicit working directory.

### Fall back from `workdir` to the hook process directory

A fallback can hide missing protocol data and produce different decisions for
the same tool request. The strict exception should fail closed instead.

## Components and Data Flow

1. The shell tool requests a command and `workdir`.
2. Codex sends both values in the `PreToolUse` payload.
3. `codex-block-git-push-main` extracts both values.
4. The embedded Python validator supplies `workdir` as `cwd` to all Git checks
   used by the Sites exception.
5. The command is allowed only when the existing strict command and repository
   checks pass in that directory.

## Error Handling

A missing directory, an invalid directory, a failed Git process, or a non-Git
directory does not qualify for the exception. The hook returns the existing
main-push denial.

## Testing and Verification

- Add a production-hook regression that starts the hook in a parent directory,
  puts the Site repository in `.tool_input.workdir`, and allows the existing
  authenticated publish command.
- Confirm the same payload is denied when `workdir` is missing, invalid, or not
  a Git repository.
- Run both managed-hook suites and shell syntax checks.
- Provision the repository-managed hook.
- Exercise the deployed hook from a parent directory with a Site repository in
  `.tool_input.workdir`.

## Rollout

Provision the updated hook. No data migration or hook registration change is
required.
