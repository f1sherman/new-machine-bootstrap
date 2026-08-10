# Name-Only Agent Session Registry Design

**Date:** 2026-08-09
**Status:** Approved for planning

## Purpose

The agent session registry currently stores both `name` and `goal`. NMB PR #441 removes Pi's separate goal state and makes the built-in Pi session name the single session identity. The registry must use the same model.

This change removes `goal` from the public registry and updates NMB integration to publish only the Pi session name.

## Scope

The change will:

- release `f1sherman/agent-session-registry` version `0.2.0`;
- remove `goal` from its database, record model, CLI, output, documentation, and tests;
- migrate existing version 1 databases to a name-only version 2 schema;
- update NMB to pin `v0.2.0`;
- integrate registry publication with the name-only managed hook from NMB PR #441.

The change will not add a daemon, browser interface, network service, arbitrary metadata, or inferred session completion.

## Public Registry Contract

A record contains these fields:

- `source`: adapter namespace, such as `pi`;
- `hostname`: canonical machine hostname;
- `session_id`: source-native session identifier;
- `remote`: whether the session runs remotely;
- `status`: `active` or `done`;
- `name`: the single user-facing session identity;
- `cwd`: session working directory;
- `adapter`: external adapter name;
- `adapter_config`: adapter-specific JSON object;
- `created_at`: creation timestamp;
- `updated_at`: last-change timestamp.

The composite identity remains `(source, hostname, session_id)`.

The `register` and `update` commands will not accept `--goal`. JSON and human output will not contain `goal`. All other command and adapter behavior remains unchanged.

## Database Migration

Schema version 2 removes the `goal` column. Migration will run in one immediate transaction:

1. Create a version 2 replacement table without `goal`.
2. Copy all version 1 columns except `goal`.
3. Drop the version 1 table.
4. Rename the replacement table to `sessions`.
5. Set `PRAGMA user_version = 2`.

Migration preserves each existing `name` exactly. It discards `goal`, including when `name` is empty. No compatibility fallback copies `goal` into `name`.

If any migration step fails, the transaction rolls back and leaves the version 1 database intact.

## NMB Integration

Implementation will wait for NMB PR #441 to merge. PR #443 will then merge updated `main` and resolve its hook conflicts by keeping the consolidated name-only model.

The managed hook will:

- register each persistent Pi session with its built-in session name;
- update the registry from `session_info_changed` when the name changes;
- omit all registry goal arguments and goal updates;
- serialize registry operations so newer names win;
- keep registry work nonblocking and failure-isolated;
- skip ephemeral sessions that lack a session ID or session file;
- never mark a session done during shutdown.

The existing `z-session-done` skill remains the only managed completion path. It runs only after an explicit user request and supplies the current Pi session ID to `asr done`.

## Errors and Compatibility

Opening a database with a schema version newer than 2 will fail before mutation. Invalid or removed `--goal` arguments will produce the normal concise CLI input error and exit status 2.

The release is `v0.2.0` because removing a record field and CLI option changes the public contract. NMB will pin the immutable `v0.2.0` Git tag.

## Verification

Public registry tests will verify:

- version 1 records migrate to version 2;
- all retained fields remain unchanged;
- migration discards `goal` without copying it into `name`;
- rollback preserves the version 1 database on failure;
- `goal` is absent from schema, record output, and help;
- `--goal` is rejected;
- register, update, list, show, done, resume, concurrency, and adapter safety still work.

NMB tests will verify:

- persistent session registration includes `name` and no `goal`;
- name changes publish in order;
- slow or failed registry commands do not block Pi;
- ephemeral sessions do not register;
- shutdown never marks a session done;
- the Pi adapter still resumes by session file.

Final verification will run the public Ruby suite, NMB focused tests, Ansible syntax validation, provisioning, and a live persistent Pi register/name/done/resume/shutdown cycle.

## Rollout

1. Merge NMB PR #441.
2. Implement, review, and publish public registry `v0.2.0`.
3. Merge updated `main` into PR #443 without rewriting its published history.
4. Adapt PR #443 to name-only publication and pin `v0.2.0`.
5. Provision and run end-to-end verification.
6. Update PR #443 and resume monitoring.
