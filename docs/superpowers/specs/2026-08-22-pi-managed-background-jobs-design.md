# Pi Managed Background Jobs Design

**Status:** Self-approved

## Goal

Reduce idle time in Pi sessions when an agent starts a known long-running command.
Pi will start the command as a managed background job. The agent can do read-only
work while the job runs. Pi will inject the result and automatically continue the
session when the job ends.

The first release supports these managed commands:

- `bin/provision` and `./bin/provision`, with arguments
- `bin/test` and `./bin/test`, with arguments
- `bin/test-ruby` and `./bin/test-ruby`, with arguments
- A simple `ssh` command whose remote command is one supported command

## Non-goals

- Do not background arbitrary shell commands.
- Do not infer long-running commands from elapsed time.
- Do not support shell pipelines, lists, redirections, substitutions, or wrappers
  in an automatically managed command.
- Do not run more than one managed job in one Pi session.
- Do not recover a running child after the Pi process crashes.
- Do not change user-entered `!` or `!!` commands.
- Do not provide a general job scheduler.

## Assumptions

- The command allowlist is managed with the extension in this repository.
- Read-only work means only the `read`, `grep`, `find`, and `ls` tools.
- The agent must not edit files, start subagents, or run another shell command
  while a managed job is active.
- A user can cancel a managed job with an explicit Pi command.
- Escape does not cancel a detached managed job.
- Pi terminates the process group during a normal Pi quit. This prevents orphan
  jobs. Extension reload preserves the job.
- Pi blocks session replacement and session fork while a job is active.
- A simple SSH form can contain SSH options and one host. The remote command must
  be one quoted shell word or the remaining SSH arguments. The remote command can
  start with a simple `cd PATH &&` prefix.
- Commands that the strict classifier does not recognize continue to use the
  normal synchronous Bash tool.

## Approaches

### Recommended: Override the Bash tool with a strict classifier

Register a replacement tool named `bash`. Delegate normal commands to Pi's
built-in Bash tool. Spawn allowlisted commands as detached managed jobs.

Set the replacement tool to sequential execution. This makes the gate active
before Pi starts a sibling tool call from the same assistant message.

Advantages:

- Existing `tool_call` safety hooks still see the tool name `bash`.
- Normal Bash behavior stays unchanged for commands outside the allowlist.
- The extension can return immediately after it starts a managed job.
- One component owns classification, process state, tool gating, and completion.

Risks:

- The extension must preserve Pi session environment variables for managed jobs.
- Shell classification must fail closed. An ambiguous command must stay
  synchronous.
- Reload needs process-global state so it does not lose the running child.

### Alternative: Add a separate background-job tool

Add a new tool and ask the model to choose it for long commands.

This is simpler, but it is not automatic. Model selection can vary. Existing
Bash guards would not automatically apply to a different tool name.

### Alternative: Return early from a `tool_call` hook

Intercept Bash tool calls in an event hook.

Pi hooks can block or mutate a tool call. They cannot return a successful custom
result. This approach cannot implement the required behavior.

## Architecture

### Bash override

The extension creates Pi's built-in Bash tool and registers a replacement with
these properties:

- The name remains `bash`.
- The parameter schema, description, prompt data, and renderers come from the
  built-in definition where practical.
- `executionMode` is `sequential`.
- Nonmatches call the built-in tool without modification.
- A match starts one managed job and returns a short result with its job ID,
  process ID, command, start time, and log path.

The sequential mode is a safety boundary. Without it, Pi can validate and start
sibling tool calls in parallel before the extension limits the active tools.

### Strict command classifier

The classifier uses a small shell-word parser. It accepts plain, single-quoted,
double-quoted, and backslash-escaped words. It rejects shell control syntax at
command level.

A local command matches only when its executable is an exact allowlisted path.
Arguments can be ordinary shell words. The classifier does not rewrite the raw
command.

An SSH command matches only when:

1. The local executable is `ssh`.
2. Options and their required values are complete.
3. There is exactly one destination.
4. The remote command parses as a supported local command, with an optional
   `cd PATH &&` prefix.
5. No additional shell operation exists outside that remote command.

If parsing is incomplete or ambiguous, the command is not a match.

### Process and log management

The extension starts the raw command with the configured shell and `-lc`. It
uses a detached process group. Standard input is closed. Standard output and
standard error go to one mode `0600` log file in a mode `0700` session-specific
directory below the system temporary directory.

The child receives Pi's current shell environment plus current values for:

- `PI_SESSION_ID`
- `PI_SESSION_FILE`, when the session is persistent
- `PI_PROVIDER`
- `PI_MODEL`
- `PI_REASONING_LEVEL`

The job record contains the process, process group ID, command, working
directory, timestamps, log path, saved active tools, and completion state.
Process-global state under `Symbol.for(...)` keeps the record across `/reload`.
Only one job can be active.

### Read-only gate

Immediately after a successful spawn, the extension saves the exact active tool
list. It then activates only tools from this set that were already active:

- `read`
- `grep`
- `find`
- `ls`

A `tool_call` handler is a second boundary. It blocks every tool except these
four while a job is active. This protects the session if another extension
changes the active tool list.

The completion path restores the exact saved tool list. It restores tools once,
even when cancellation and process exit race.

### Completion and automatic continuation

When the child exits, the extension:

1. Marks the job complete.
2. Restores the saved active tools.
3. Reads a bounded tail from the log.
4. Builds a completion message with the job ID, exit status or signal, duration,
   log path, and tail.
5. Injects the message with `triggerTurn: true` and `deliverAs: "steer"`.

The injected message lets the agent inspect the result and continue without a
new user message. The complete output remains in the log file.

### Commands and lifecycle

The extension registers:

- `/background-jobs`: Show the active job or the most recent result.
- `/background-cancel`: Send `SIGTERM` to the active process group. Send
  `SIGKILL` after a short grace period if it does not stop.

`session_before_switch` and `session_before_fork` cancel the requested session
operation while a job is active. The extension shows a clear reason.

On extension reload, the old runtime leaves the process running. The new runtime
reattaches the gate and completion controller through process-global state. On
normal Pi quit, the extension terminates the process group. Crash recovery is
out of scope.

## Errors

- If spawn fails, restore tools and return a Bash tool error. Do not create a job.
- If log creation fails, return an error and do not start the child.
- If a job is already active, an allowlisted Bash call returns an error. The
  read-only gate normally prevents this path, but the check remains required.
- If completion cannot read the log, inject metadata without a tail.
- If tool restoration or message injection fails, write a warning. Keep the log
  and completion metadata available through `/background-jobs`.
- A nonzero child exit is a completed job, not an extension failure. The
  completion message reports the exit status.

## Testing and verification

Add a behavioral Node harness under `tests/` that loads the production extension
with controlled process adapters. The tests will verify:

- Local and SSH allowlist matches.
- Complex and unsupported commands delegate unchanged.
- A managed call returns before the controlled child completes.
- The Bash override uses sequential execution.
- The extension limits active tools to the read-only set.
- The fail-safe hook blocks other tool calls.
- Success, failure, cancellation, and completion inject the correct result.
- Completion restores the exact active tool list once.
- Reload preserves an active job and reapplies the gate.
- Session switch and fork are blocked while a job is active.
- Pi session environment values reach the managed child.

Register the test in the existing integration workflow. Install the extension
through the existing common-role extension tasks.

Run focused tests first. Then run the repository CI test entry point. Run
provisioning for the local machine and `dev` after verification so both Pi
installations receive the extension.

## Rollout

1. Install the extension through the common Ansible role.
2. Provision the local machine.
3. Provision `dev` with the common role path used by its inventory assignment.
4. Start a fresh Pi session on each machine.
5. Run one allowlisted test or provisioning command and confirm that Pi returns
   immediately, limits tools, injects completion, and resumes.

The strict classifier limits the first rollout. Unsupported forms remain
synchronous and preserve current behavior.
