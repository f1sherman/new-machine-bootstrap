# Pi stale-session notifier

Date: 2026-08-14
Status: Proposed

## Goal

Notify each running Pi process when its loaded setup no longer matches the
effective setup on disk. Tell the user whether `/reload` is sufficient or a
new Pi process is required.

The warning must remain visible until the user takes the required action. A
no-op provision must not warn. A source edit that has not been deployed must
not warn.

## Non-goals

- Automatically reload or restart Pi.
- Detect arbitrary file changes outside declared Pi resource owners.
- Treat a Git commit, branch change, or repository pull as deployed state.
- Reload shell credentials or application credentials.
- Change Pi session storage or transcript behavior.
- Add project-specific filtering in the first version.
- Replace Pi's `/reload` command.

## Assumptions

- `new-machine-bootstrap` (NMB) owns the Pi executable, base Pi resources, and
  tmux indicator transport.
- A private producer owns managed extensions, skills, packages, and the
  project package store that it reconciles.
- Each participating repository can use the same publisher contract.
- Standard provisioning is cooperative. Each repository declares the
  effective deployed inputs that it owns.
- A global producer change can warn every Pi process. Project-scoped warnings
  are deferred until false positives show that they are necessary.
- Existing Pi processes need one `/reload` or restart after initial rollout to
  load the new watcher.

## Approaches considered

### 1. Producer fingerprints and a Pi watcher extension

Each provisioner publishes deterministic fingerprints for the effective Pi
inputs that it owns. A Pi extension polls the compact producer state and shows
a persistent warning when a fingerprint differs from its loaded baseline.

This is the recommended approach. It separates resource ownership from user
interface behavior. It detects no-op provisions correctly. It also supports
Pi processes outside tmux.

### 2. Watch Pi files directly

The extension could recursively watch `~/.pi/agent`, project `.pi`
directories, and installed packages.

This approach is not selected. Atomic replacement can invalidate file
watchers. Broad directory watches include sessions, caches, and credentials.
Narrow watches cannot reliably determine package precedence or the effective
package resource set. File locations also cannot reliably distinguish reload
changes from process-start changes.

### 3. Signal running tmux panes after provisioning

Provisioning could enumerate panes and send a tmux option or input to each Pi
process.

This approach is not selected. It misses Pi outside tmux. It races with pane
creation and closure. It also loses the warning when a pane or client is not
available at publication time.

## Ownership

NMB owns the generic feature:

- the state publisher command;
- the state schema and fingerprint rules;
- the Pi watcher extension;
- the `@pi_stale` tmux pane option;
- the local and remote tmux badge rendering;
- NMB's own Pi resource manifest.

A private producer owns only its producer declaration and reconciliation
calls. Each later participating repository uses the NMB publisher without
copying its implementation.

## State contract

### Location and permissions

Producer records live under:

```text
${XDG_STATE_HOME:-~/.local/state}/pi-session-staleness/v1/producers/
```

The directory mode is `0700`. Each producer record is a `0600` JSON file. The
producer identifier must match `[a-z0-9][a-z0-9-]{0,63}`. The initial producer
identifier is `new-machine-bootstrap`. A later participating repository
selects its own identifier when it enrolls.

Each producer writes only its own file. This prevents one repository from
removing another repository's state.

### Record schema

```json
{
  "schema": 1,
  "producer": "new-machine-bootstrap",
  "reload": {
    "generation": "sha256:0123456789abcdef...",
    "changedAt": "2026-08-14T15:04:05.000Z",
    "reason": "Managed Pi resources changed"
  },
  "restart": {
    "generation": "sha256:fedcba9876543210...",
    "changedAt": "2026-08-14T15:04:05.000Z",
    "reason": "Managed Pi runtime changed"
  }
}
```

`reload` and `restart` are optional during initial enrollment. Each record is
updated independently. `generation` is a fingerprint of the current effective
state. It is not a counter. If state changes from A to B and back to A before a
poll, a process that loaded A is correctly considered current.

`reason` is a short, fixed description from the producer. It must not contain
credentials, file contents, diffs, command arguments, or other untrusted text.

### Fingerprints

The publisher hashes a canonical, sorted manifest. A path input contributes:

- its manifest name;
- its relative path within the declared root;
- file, directory, or symbolic-link type;
- executable mode when execution behavior depends on it;
- symbolic-link target;
- file bytes.

A missing declared input contributes an explicit missing-value sentinel.
Directory traversal order must not affect the result. File timestamps,
ownership, and unrelated mode bits do not affect the result.

Producers must declare only effective Pi inputs. They must exclude sessions,
transcripts, auth files, logs, caches, generated usage data, and other mutable
runtime state.

Package declarations must cover the effective installed package. The
producer can hash the installed package content or a verified immutable
package integrity and version. Hashing only `settings.json` is insufficient
because an unpinned package can change without changing that file. A package
with a repository-owned overlay must include the overlaid installed content.

### First enrollment

An extension instance treats all valid producer records present at startup as
its baseline. A producer file that first appears after startup is a change.
This makes later resource owners fail safe.

During initial rollout, NMB creates its producer baseline before it installs
the watcher. New Pi processes therefore start with a complete baseline.

## Publisher interface

NMB installs a Ruby command named `pi-session-staleness-publish`. The command
accepts these inputs:

- operation: `reconcile`;
- producer identifier;
- classification: `reload` or `restart`;
- fixed reason;
- a JSON manifest of path and value inputs.

The command computes the fingerprint. It changes the producer record only
when that classification's fingerprint changed. A no-op reconcile leaves the
file bytes and modification time unchanged.

The command validates the producer identifier, schema, classification,
manifest roots, and reason length. It locks same-producer updates. It writes a
temporary file in the state directory, flushes it, and renames it over the
destination. Readers must never observe partial JSON.

The command logs validation, read, hash, lock, and write failures. It does not
replace a valid record after a failure.

## Change classification

### Reload required

The following changes increment a producer's `reload` generation:

- Pi `settings.json`, `models.json`, or `keybindings.json`;
- global context files loaded by Pi;
- extensions, skills, prompts, and themes;
- Pi package membership, version, or effective content;
- package-provided tools;
- load-time MCP configuration;
- project package store content changed by managed provisioning.

Pi `/reload` re-resolves settings and packages and reloads these resources.

### Process restart required

The following changes increment a producer's `restart` generation:

- the Pi executable or Pi package runtime;
- the managed Node.js runtime used by Pi;
- Pi launch flags;
- environment or startup inputs already captured by the process;
- project trust state.

When a change could be either class, the producer uses `restart` and documents
the reason in its manifest definition. Restart has precedence over reload in
the user interface.

### No signal

The following changes do not update either generation:

- unrelated or no-op provisioning;
- source edits that were not deployed;
- scripts and executables that Pi reads fresh on each call;
- transcripts and session state;
- credentials that have their own refresh path;
- tmux configuration that provisioning already applies to the live server.

## Provisioning lifecycle

Each participating repository reconciles its declared state after possible
Pi mutations. Ansible check mode never publishes because it does not change
effective state. An apply run publishes even when --diff is enabled, because
--diff changes only reporting and does not make the run read-only.

Reconciliation must also run from the provisioner's cleanup path after a
partial failure. This is necessary because a failed provision can still
change effective Pi files. Deterministic fingerprints prevent a cleanup
reconcile from creating a false warning when no effective input changed.

If reconciliation fails after an otherwise successful provision, the
provision fails. If provisioning already failed, the original failure remains
primary and the reconciliation failure is also printed and logged.

The existing provision lock serializes normal runs. The publisher still uses
atomic per-producer writes so future independent publishers are safe.

NMB's manifest covers its Pi executable, Node runtime identity, base settings,
models, keybindings, context, extensions, and skills. A private producer's
manifest covers its installed extensions, skills, managed packages, settings
changes, and project package store content that it actually mutates.

## Extension lifecycle

NMB installs a global Pi extension named `pi-session-staleness.ts`.

The extension maintains two baselines:

- reload generations for the current successfully loaded extension instance;
- restart generations for the current Pi process.

Process-wide restart state uses a stable process-global key so it survives Pi
resource reloads. Reload state is replaced only after a new extension instance
reads a complete valid snapshot and reaches `session_start`. A failed reload
or invalid snapshot does not clear an existing warning.

On `session_start`, the extension starts a 10-second polling loop. A directory
watch can request an early poll, but polling is the correctness mechanism.
Atomic replacement and missing files must not disable later checks.

The extension compares every valid producer file with its baselines:

- a changed reload generation requires `/reload`;
- a restart record newer than the process baseline requires a new Pi process;
- restart wins when both apply.

`/reload`, `/new`, `/resume`, and `/fork` clear reload staleness only after the
replacement resource set starts successfully. A restart warning remains for
the life of the process. Starting a new Pi process captures the current state
and clears both classes.

The extension sends one warning notification for each new generation. It can
notify again for a later generation or when severity increases from reload to
restart. It does not repeat a notification on every poll. Notification
deduplication also uses process-global state so `/reload` does not repeat a
restart notification.

On `session_shutdown`, the extension stops its poller and directory watch. It
also clears its tmux pane option when the process is exiting. Pi reload teardown
can clear the option briefly; the replacement instance republishes any
remaining restart warning.

The extension never calls `ctx.reload()` and never exits Pi automatically.

## User interface

For reload staleness, Pi shows a persistent yellow footer status:

```text
↻ Pi changed — /reload
```

For restart staleness, Pi shows a persistent red footer status:

```text
⟳ Pi changed — restart Pi
```

The first notification includes the producer and its short reason. The footer
stays short and does not list paths or multiple changes.

If state cannot be parsed or checked, the extension logs the error once per
distinct failure and continues polling. It shows `Pi staleness check failed`
unless a stronger stale warning is already visible. Malformed, unsupported,
or temporarily missing state must never clear a known stale warning.

A missing state directory on a new machine is normal until the first producer
is enrolled.

## Tmux contract

When `$TMUX_PANE` is present, the extension publishes:

```text
@pi_stale = reload | restart
```

It removes the option when the process is current or exits. After a change, it
requests the existing `tmux-window-label` and `tmux-remote-title publish`
refresh paths. Tmux failures are logged at a limited rate and do not interrupt
Pi.

NMB adds the badge to its existing Pi indicator pipeline:

- `reload` renders `↻`;
- `restart` renders `⟳`;
- restart has precedence.

The remote title marker extends from two fields to three:

```text
[nmb-ind=<activity>,<pr-state>,<pi-stale>]
```

Readers accept both the old two-field form and the new three-field form.
Unknown values render no stale badge. Multi-pane windows keep the current
active-pane behavior, so switching panes recalculates the window label.

## Error handling and security

- State parsing is strict. Unknown schema versions are errors.
- One invalid producer cannot hide valid stale state from other producers.
- A read error does not reset the last known good state.
- Publisher errors are never silently ignored.
- Extension and tmux errors are rate-limited so a persistent failure does not
  flood the session or logs.
- State contains fingerprints and fixed reasons only. It contains no secrets
  or copied configuration.
- The extension reads only the versioned state directory. It does not execute
  producer-controlled commands.

## Testing and verification

### Publisher behavior

Production-command tests cover:

- stable fingerprints across traversal order;
- content, symlink target, executable mode, and missing-path changes;
- no-op reconciliation leaving the record unchanged;
- updating only the requested classification;
- independent producer records;
- invalid schema, identifier, class, manifest, and path failures;
- atomic reads during replacement;
- preservation of the prior record after failure.

These tests protect state correctness and concurrent reader behavior. They do
not assert documentation text or an Ansible task list.

### Extension behavior

A Node integration test loads the production extension with injectable state,
polling, UI, process-global storage, and tmux execution. It covers:

- startup baseline and a later producer enrollment;
- reload and restart transitions;
- restart precedence;
- notification deduplication and severity escalation;
- malformed, unsupported, missing, and restored state;
- shutdown cleanup;
- extension replacement clearing reload state;
- process-global restart state surviving extension replacement.

### Tmux behavior

Existing NMB label contract tests cover:

- local reload and restart badges;
- restart precedence;
- the old two-field and new three-field remote markers;
- remote badge propagation and marker stripping;
- pane option cleanup and active-pane recalculation.

The tests verify state mapping and transport compatibility. Exact prose is not
tested.

### End-to-end verification

Use two running Pi processes and verify these behaviors empirically:

1. A second no-op provision leaves producer records unchanged.
2. An unrelated provision change creates no warning.
3. An NMB reload-class resource change warns both processes.
4. `/reload` clears the reload footer and tmux badge.
5. A simulated runtime change survives `/reload` and clears only in a new Pi
   process.
6. A managed package or private producer extension change produces the same
   reload warning.
7. A failed provision that changed a declared Pi input still warns.
8. Local and remote development host Pi panes show the correct tmux badge.

## Rollout

### Phase 1: NMB

NMB adds the publisher, NMB manifests, watcher extension, and backward-
compatible tmux transport. Provisioning creates the NMB baseline before it
installs the watcher.

After deployment, run one explicit `/reload` or restart in each existing Pi
process that should receive future warnings. Verify a controlled reload-class
change locally and on one remote development host.

### Phase 2: Private producer

A private producer registers and reconciles the effective managed resources it
owns. Its first producer record warns Pi processes that were already running
because a new resource owner appeared after their baseline.

Verify a managed package change and a private producer extension change.
Confirm that a second no-op private producer provision does not modify the
producer record.

### Future producers

A repository that changes effective Pi setup adds a manifest and invokes the
publisher. It must classify each declared input and prove no-op behavior. It
must not edit another producer's record.

## Acceptance criteria

- Every cooperative provisioner can publish reload and restart fingerprints
  without copying publisher logic.
- No-op and unrelated provisions do not warn.
- Two running Pi processes detect a deployed change within 15 seconds.
- Reload warnings clear after a successful `/reload`.
- Restart warnings survive `/reload` and clear only in a new Pi process.
- The Pi footer and local or remote tmux tab retain the warning until it is
  resolved.
- Invalid state does not clear a valid warning or stop future checks.
- A partial failed provision still records effective Pi drift.
- State records contain no configuration contents or credentials.

## Risks and limits

- An undeclared effective input causes a false negative. Each producer's
  manifest must be reviewed when it adds a new Pi resource.
- An overly broad manifest causes false positives and slower reconciliation.
- Direct project-local `.pi` edits are not detected unless that repository
  publishes state. Guessing Pi's resolved package set is intentionally out of
  scope.
- A global project package store change can warn sessions in unrelated
  projects. Project-scoped records are a later extension if this becomes
  noisy.
- Existing processes cannot use a watcher that they have not loaded. The
  rollout requires one explicit reload or restart.
