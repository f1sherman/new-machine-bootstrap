# ChatGPT Sites Working Directory Design

**Status:** Self-approved

## Goal

Make the Codex ChatGPT Sites push exception validate Git state in an explicit
repository directory that survives the live hook boundary.

## Non-goals

- Do not broaden the allowed command shapes, hosts, refspecs, or authentication
  settings.
- Do not parse `cd`, wrappers, or repository-selection syntax other than one
  strict `git -C <absolute path>` prefix.
- Do not change the Pi guard, which already receives its selected working
  directory as an explicit argument.

## Evidence and Assumptions

- A captured failing Site publish tool call contains a `workdir` field that
  points to the generated Site repository.
- The Codex hook currently reads only `.tool_input.command` and runs every Git
  subprocess in the hook process directory.
- The same redacted publish command passes when the hook process starts in the
  Site repository and fails when it starts in the parent directory.
- The live Codex `PreToolUse` payload omits the shell tool's requested
  `workdir`. It contains the session directory as top-level `.cwd` and only the
  command as `.tool_input.command`.
- The per-command directory must therefore be present in the command that the
  hook evaluates.

## Recommended Approach

Allow one additional strict Sites command shape with `git -C <absolute path>`
before the existing plain or authenticated push form. Use that path for every
Git subprocess in the strict Sites exception. Keep the normal push-blocking
analysis unchanged.

Continue to support the existing form when the hook process already runs in the
Site repository. Do not use `.tool_input.workdir` because live Codex does not
send it. Require exactly one `-C`, an absolute path, and a valid Git repository.
Missing, relative, repeated, or invalid paths keep the fail-closed denial.

## Alternatives Considered

### Continue to use the hook process directory

This preserves current code but does not represent the shell tool request. It
causes the reported false denial.

### Recover `workdir` from the hook payload or transcript

The live payload does not contain the field. Reading the session transcript by
tool ID would couple approval to an unstable file format and timing.

### Infer the Site repository below the session directory

Directory discovery can select the wrong repository and makes the policy depend
on generated folder layouts. An explicit `git -C` path is unambiguous.

## Components and Data Flow

1. The shell command includes `git -C <absolute Site repository>`.
2. Codex sends the complete command in `.tool_input.command`.
3. `codex-block-git-push-main` extracts the single explicit repository path.
4. The embedded Python validator supplies that path as `cwd` to all Git checks
   used by the Sites exception.
5. The command is allowed only when the existing strict destination, refspec,
   authentication, and repository checks pass in that directory.

## Error Handling

A relative, missing, repeated, invalid, or non-Git `-C` directory does not
qualify for the exception. A failed Git process also keeps the existing
main-push denial.

## Testing and Verification

- Add a production-hook regression that starts the hook in a parent directory
  and allows an authenticated push with `git -C <Site repository>`.
- Confirm a separate tool `workdir` field does not qualify the command because
  it is absent from the live hook contract.
- Confirm relative, missing, repeated, and non-repository `-C` paths are denied.
- Run both managed-hook suites and shell syntax checks.
- Provision the repository-managed hook.
- Exercise the deployed hook from a parent directory with an explicit
  `git -C <Site repository>` command.

## Rollout

Provision the updated hook. No data migration or hook registration change is
required.
