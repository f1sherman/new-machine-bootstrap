# Agent Session Registry Design

## Problem

Agent sessions can become difficult to find after a laptop restart, a network interruption, or time away from the work. Pi gives each persistent session a stable UUID. NMB's managed Pi extension also creates a durable broad goal and keeps the visible session name current. That identity is not collected in one place, and there is no explicit record of whether the work is active or done.

A machine can also orchestrate agent sessions that run on remote hosts. Those sessions need the same local recovery view, an explicit remote marker, and a pluggable way to act on them.

The registry is useful outside NMB and outside Pi. Its core must therefore live in a small public repository with an agent-system-neutral interface.

## Goals

- Create a public `f1sherman/agent-session-registry` GitHub repository under the MIT License.
- Keep one independent session registry on each machine.
- Provide one Ruby executable named `asr`.
- Register persistent local Pi sessions deterministically from their native session UUID.
- Keep the stored Pi name and durable goal current when either value changes.
- Let local orchestrators register sessions that run on remote hosts.
- Store an explicit hostname and local-or-remote marker for each session.
- Support only `active` and `done` lifecycle states.
- Mark a session done only when the user explicitly requests it.
- Dispatch session actions through named external adapters with structured configuration.
- Define the adapter interface now, with `resume` as its first action.
- Work without a daemon or network service.
- Keep the schema suitable for a later read-only browser interface.

## Non-goals

- Do not synchronize registries between machines.
- Do not add a daemon, web service, browser interface, or network listener.
- Do not infer completion from task success, pull-request state, shutdown, inactivity, or a goodbye.
- Do not store arbitrary metadata.
- Do not store or execute arbitrary commands from session records.
- Do not register ephemeral Pi `--no-session` runs.
- Do not put NMB provisioning or Pi-specific integration in the public registry repository.
- Do not add compatibility inference for records that predate the registry.

## Repository Boundary

### Public registry repository

The public repository is:

```text
https://github.com/f1sherman/agent-session-registry
```

It owns:

- the Ruby `asr` CLI;
- the SQLite schema and migrations;
- record identity, validation, persistence, filtering, and formatting;
- active and done lifecycle operations;
- adapter discovery and action dispatch;
- the action-based adapter contract;
- CLI, database, concurrency, and adapter tests;
- user and adapter-author documentation;
- the MIT License.

It is agent-system-neutral. It does not know how Pi stores sessions and does not install NMB-managed files.

### NMB repository

NMB owns:

- installation of a pinned public registry Git tag;
- the Ruby `sqlite3` runtime dependency;
- the Pi-specific `pi-local` adapter;
- automatic Pi registration, name publication, and goal publication;
- the user-invoked `z-session-done` Pi skill;
- provisioning and integration verification on macOS and Debian.

## Public Repository Structure

The initial public repository contains:

```text
agent-session-registry/
├── LICENSE
├── README.md
├── Gemfile
├── Rakefile
├── VERSION
├── bin/
│   └── asr
├── lib/
│   └── agent_session_registry/
│       ├── adapter.rb
│       ├── cli.rb
│       ├── database.rb
│       ├── identity.rb
│       └── record.rb
└── test/
    ├── adapter_test.rb
    ├── cli_test.rb
    └── database_test.rb
```

`LICENSE` contains the standard MIT License. Tests use Minitest. `Gemfile` declares `sqlite3`. `VERSION` starts at `0.1.0`. The first public Git tag is `v0.1.0`.

The repository is installed from Git rather than published to RubyGems in version 1.

## Architecture

Each machine owns one local registry:

```text
Pi managed extension ───┐
                       ├── asr CLI ── SQLite database
Remote orchestrators ──┘      │
                              └── external action adapters
```

`asr` is the only supported database writer. Pi hooks and remote orchestrators call it. It reads and writes SQLite directly, so registration does not depend on another process.

## Storage

The database lives at:

```text
~/.local/state/agent-session-registry/registry.sqlite3
```

The state directory uses mode `0700`. The database uses mode `0600`. SQLite uses WAL mode and a busy timeout so separate Pi processes and orchestrators can update the registry safely.

The CLI uses the `sqlite3` gem. The schema uses `PRAGMA user_version`. Version 1 creates the table on demand. An unsupported newer schema version fails closed.

Tests can override the database and adapter locations through documented environment variables. Production defaults remain fixed under the user's home directory.

## Record Identity

A record has the composite primary key:

```text
(source, hostname, session_id)
```

The CLI renders it as:

```text
<source>:<hostname>:<session_id>
```

Source and hostname values are normalized to lowercase and must match `[a-z0-9][a-z0-9._-]*`. A session ID must match `[A-Za-z0-9][A-Za-z0-9._-]*`. Colons are invalid inside identity fields, so the rendered key parses without escaping or heuristics.

The CLI gets its canonical local hostname from Ruby's `Socket.gethostname`, converts it to lowercase, and removes one trailing dot. It applies the same case and trailing-dot normalization to supplied remote hostnames.

Re-registering the same identity updates its record instead of creating a duplicate. Identity columns cannot change after registration.

For a local Pi session:

- `source` is `pi`;
- `hostname` is the canonical local hostname selected by `asr`;
- `session_id` is Pi's session UUID.

Remote orchestrators choose their source namespace and supply the hostname where the session runs.

## Record Columns

| Column | Purpose |
|---|---|
| `source` | Names the integration that owns the session. It prevents native IDs from different systems from colliding. |
| `hostname` | Identifies the machine where the session runs. Local records use the canonical local hostname. Remote records use the remote host's name. |
| `session_id` | Stores the integration's native stable session ID. Pi uses `SessionManager.getSessionId()`. |
| `remote` | Explicitly records whether the session runs remotely. The registry does not infer location by comparing hostnames. |
| `status` | Stores only `active` or `done`. Registration and resume set `active`. Only an explicit completion operation sets `done`. |
| `name` | Stores the current visible session name. It can differ from the goal after a manual Pi `/name`. |
| `goal` | Stores the durable broad objective maintained by `set_session_goal`. |
| `cwd` | Shows the session's working directory. It helps the user distinguish records but does not control adapter behavior. |
| `adapter` | Names the external adapter executable used for session actions. |
| `adapter_config` | Stores the structured JSON object passed to adapter actions. It is adapter configuration, not arbitrary metadata. |
| `created_at` | Records when this machine first registered the identity. Upserts preserve it. |
| `updated_at` | Records the most recent registry mutation in UTC. |

## Ruby CLI

The human-facing commands are:

```text
asr list
asr list --all
asr list --status done
asr list --remote
asr show <key>
asr resume <key>
```

`list` shows active sessions by default and orders them by newest update first. Each human-readable entry includes:

- the registry key;
- local or remote location;
- hostname;
- current name;
- goal when it differs from the name;
- working directory;
- last update time;
- the exact `asr resume <key>` command.

`--all` includes done records. `show` prints all stored fields. Read commands support `--json` for orchestrators and future integrations.

Integration-facing operations include:

```text
asr register ...
asr update <key> ...
asr update --source <source> --session-id <id> ...
asr done <key>
asr done --source <source> --session-id <id>
```

The key forms support local and remote orchestrators. In either field form, omitting `hostname` selects the canonical local hostname. The command fails if the exact resulting identity is missing. It never searches other hostnames or selects a fallback. This lets local Pi hooks update their record without reproducing hostname normalization.

`asr --help` is the authoritative command and option reference. There is no general registry skill.

## Adapter Interface

External adapter executables live under:

```text
~/.local/lib/agent-session-registry/adapters/
```

A record contains an adapter name, not a command. Adapter names use the same restricted lowercase name format as sources. The CLI resolves only a direct executable child of the configured adapter directory. It rejects separators and traversal.

The interface is action-based:

```text
<adapter> <action> <registry-key> <adapter-config-json>
```

Version 1 defines the `resume` action. For example:

```text
pi-local resume pi:workstation:019fe7a6-a219-7548-a6ef-1f23885864f \
  '{"session_file":"/home/user/.pi/agent/sessions/example.jsonl"}'
```

The CLI invokes the adapter directly with Ruby process APIs. It does not invoke a shell. The adapter inherits the terminal standard input, output, and error streams.

`asr resume <key>` validates the record and adapter before launch. It calls `Process.spawn` with action `resume`. If process creation succeeds, it marks the record active, waits for the adapter, and returns the adapter's exit status. If process creation raises an error, it reports the error and preserves the prior status. A later adapter failure does not infer that the session is done.

The action argument makes the adapter contract extensible without predicting or implementing additional version 1 actions.

## Pi Adapter

NMB installs `pi-local` in the external adapter directory. It accepts only the `resume` action in version 1. It parses `adapter_config`, requires a readable absolute `session_file`, and executes:

```text
pi --session <session-file>
```

It rejects unsupported actions and malformed configuration with a nonzero exit. It does not interpret record fields from the registry key.

## Pi Registration and Update Flow

The existing `roles/common/files/pi/extensions/managed-hooks.ts` remains the owner of Pi goal and name state. It publishes registry changes at the following lifecycle points.

### Session start

For a persistent session, `session_start` registers or updates:

- source `pi`;
- the native Pi session UUID;
- `remote: false`;
- status `active`;
- the current name, goal, and working directory;
- adapter `pi-local`;
- adapter configuration containing the absolute session file.

A missing session file identifies an ephemeral session. The extension skips it. Registration changes a previously done record back to active.

### Goal changes

The canonical `applySessionGoal` path updates the registry after a new goal has been durably accepted. The registry does not add another evaluator and does not parse the session JSONL file.

### Name changes

`session_info_changed` updates the stored name. This includes names managed from the durable goal and manual `/name` values.

### Publication ordering and errors

Registry operations are serialized inside the extension so an older asynchronous update cannot overwrite a newer name or goal. Equivalent CLI updates do not change `updated_at`.

Registry publication errors use the managed extension's safe warning path. They do not block Pi startup, naming, goal persistence, or agent work. A later idempotent update can repair the record.

### Shutdown

Shutdown, reload, session replacement, and process loss do not mark a session done.

## Remote Registration

A local orchestrator uses the same `register` and `update` commands. It supplies:

- its source namespace;
- the remote hostname;
- the native remote session ID;
- `remote: true`;
- status, name, goal, and working directory when available;
- an adapter name;
- the adapter's structured configuration.

NMB does not define a network protocol or poll remote hosts. The orchestrator translates its own events into local `asr` calls and can install its adapter independently.

## Completion Skill

NMB provisions one Pi skill named `z-session-done`. It is user-invoked only.

The skill:

1. confirms that `PI_SESSION_FILE` is set so the current session is persistent;
2. passes the current `PI_SESSION_ID` explicitly to `asr`;
3. uses source `pi`;
4. lets `asr` select the canonical local hostname;
5. reports the session ID marked done.

Its mutation is:

```text
asr done \
  --source pi \
  --session-id "$PI_SESSION_ID"
```

The skill states that the agent must run this operation only when the user explicitly asks to mark the current session done. The agent must not infer completion from implementation success, verification, pull-request creation or merge, shutdown, inactivity, or conversational wording such as goodbye.

The skill does not accept another session ID from the user and does not construct a registry key. A missing environment value, ephemeral session, or unregistered exact identity fails without changing another record.

## Validation and Failure Handling

The CLI validates all inputs before mutation:

- source, hostname, session ID, and adapter name use their allowed formats;
- `remote` is explicit on registration;
- status is `active` or `done`;
- `adapter_config` is a JSON object;
- timestamps are generated by the CLI in UTC.

Invalid input, a missing record, a missing adapter, an adapter launch failure, a malformed database, or an unsupported schema version returns a nonzero exit and a concise diagnostic.

No command executes record content through a shell. Repeated registration, equivalent updates, and repeated done operations are idempotent. An equivalent update does not change `updated_at`.

## Public Repository Testing

Public repository tests execute the production Ruby classes and `bin/asr` against temporary state. They cover:

- deterministic composite identity and hostname normalization;
- schema initialization and unsupported-version failure;
- registration and idempotent upsert;
- local and remote records;
- preservation of `created_at`;
- name and goal updates;
- active and done filtering;
- human and JSON output;
- exact-key and local field-form completion;
- missing completion targets;
- adapter discovery, action, key, and JSON configuration delivery;
- traversal and shell-injection resistance;
- status handling when an adapter cannot start;
- concurrent updates.

## NMB Testing and Verification

NMB tests cover behavior specific to provisioning and Pi:

- installation from pinned tag `v0.1.0`;
- `asr` executable availability;
- external adapter directory and `pi-local` installation;
- registration on persistent Pi `session_start`;
- no registration for an ephemeral session;
- name updates through `session_info_changed`;
- goal updates through the canonical goal path;
- serialized publication and safe CLI failure behavior;
- resumed done sessions becoming active through registration;
- `pi-local` action and configuration validation.

The skill is verified through provisioning and an end-to-end session rather than a static wording test.

End-to-end verification will:

1. run the public repository test suite;
2. publish the approved initial repository and tag `v0.1.0`;
3. run `bin/provision` from the NMB feature worktree;
4. start a real persistent Pi session;
5. confirm its UUID, name, goal, hostname, and active state through `asr`;
6. exercise the `z-session-done` contract and confirm done state;
7. resume the session with `asr resume`;
8. confirm the resumed session becomes active again.

## NMB Deployment

NMB clones tag `v0.1.0` into:

```text
~/.local/share/agent-session-registry
```

It links the repository's `bin/asr` into `~/.local/bin/asr`. It installs the `sqlite3` gem for the pinned NMB Ruby runtime. It creates the external adapter directory and installs `pi-local` there. The Pi extension calls `asr` through the user's managed executable path.

The same components are available on macOS and Debian development hosts. No service manager, privileged port, firewall rule, or host-to-host credential is required.

## Future Browser View

A later read-only localhost browser service can query the same schema and reuse the same identity and status meanings. It must not become a second database writer. It is outside this implementation scope.
