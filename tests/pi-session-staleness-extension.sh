#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
source_file="$repo_root/roles/common/files/pi/extensions/pi-session-staleness.ts"
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
cp "$source_file" "$temporary_directory/pi-session-staleness.mjs"

SOURCE_FILE="$temporary_directory/pi-session-staleness.mjs" node --input-type=module <<'JAVASCRIPT'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const ADAPTERS = Symbol.for("nmb.pi-session-staleness.adapters");
const PROCESS_STATE = Symbol.for("nmb.pi-session-staleness.process-state");
const RELOAD_STATE = Symbol.for("nmb.pi-session-staleness.reload-state");
const STATUS_KEY = "pi-session-staleness";
const generation = (character) => `sha256:${character.repeat(64)}`;
const changedAt = "2026-02-24T12:34:56.789Z";

function record(producer, values = {}) {
  const result = { schema: 1, producer };
  for (const classification of ["reload", "restart"]) {
    if (values[classification]) {
      result[classification] = {
        generation: values[classification],
        changedAt,
        reason: values[`${classification}Reason`] ?? `${classification} resources changed`,
      };
    }
  }
  return JSON.stringify(result);
}

function resetProcessState() {
  delete globalThis[PROCESS_STATE];
  delete globalThis[RELOAD_STATE];
}

function environment(initialRecords = {}, options = {}) {
  const records = new Map(Object.entries(initialRecords));
  const handlers = new Map();
  const statuses = [];
  const notifications = [];
  const logs = [];
  const execs = [];
  const intervals = [];
  const watches = [];
  let directoryError = options.directoryError;
  let watchError = options.watchError;
  let execError = options.execError;
  const execResults = [...(options.execResults ?? [])];

  globalThis[ADAPTERS] = {
    stateDirectory: "/state/producers",
    async readDirectory() {
      if (directoryError) {
        throw directoryError instanceof Error
          ? directoryError
          : new Error(directoryError);
      }
      return [...records.keys()];
    },
    async readFile(path) {
      const name = path.split("/").at(-1);
      if (!records.has(name)) throw new Error(`missing ${name}`);
      const value = records.get(name);
      if (value instanceof Error) throw value;
      return value;
    },
    watchDirectory(_path, callback) {
      if (watchError) throw new Error(watchError);
      const handle = {
        closed: false,
        close() { this.closed = true; },
        callback,
      };
      watches.push(handle);
      return handle;
    },
    setInterval(callback, milliseconds) {
      const timer = { callback, milliseconds, cleared: false };
      intervals.push(timer);
      return timer;
    },
    clearInterval(timer) { timer.cleared = true; },
    log(message) { logs.push(message); },
    async exec(command, args) {
      execs.push([command, args]);
      if (execError) throw new Error(execError);
      return execResults.shift() ?? { code: 0, killed: false, stdout: "", stderr: "" };
    },
  };

  const pi = {
    on(name, handler) { handlers.set(name, handler); },
    exec: globalThis[ADAPTERS].exec,
  };
  const ctx = {
    hasUI: true,
    ui: {
      theme: { fg: (color, text) => `${color}:${text}` },
      setStatus(key, value) { statuses.push([key, value]); },
      notify(message, severity) { notifications.push([message, severity]); },
    },
  };

  return {
    ctx,
    execs,
    handlers,
    intervals,
    logs,
    notifications,
    pi,
    records,
    statuses,
    watches,
    setDirectoryError(value) { directoryError = value; },
    setExecError(value) { execError = value; },
    setWatchError(value) { watchError = value; },
    async start() { await handlers.get("session_start")({}, ctx); },
    async shutdown() { await handlers.get("session_shutdown")({}, ctx); },
    async poll() { await intervals.at(-1).callback(); },
    async watch() {
      watches.at(-1).callback();
      await new Promise((resolve) => setImmediate(resolve));
    },
    lastStatus() { return statuses.at(-1); },
  };
}

const moduleUrl = `${pathToFileURL(process.env.SOURCE_FILE).href}?test=${Date.now()}`;
const extension = (await import(moduleUrl)).default;
assert.equal(typeof extension, "function", "extension exports a default factory");

async function startupBaselineAndLifecycle() {
  resetProcessState();
  const env = environment({
    "alpha.json": record("alpha", { reload: generation("a"), restart: generation("b") }),
  });
  extension(env.pi);
  assert.equal(env.intervals.length, 0, "factory does not start a timer");
  assert.equal(env.watches.length, 0, "factory does not start a watcher");
  await env.start();
  assert.equal(env.intervals.length, 1, "session start creates one timer");
  assert.equal(env.intervals[0].milliseconds, 10_000, "poll interval is ten seconds");
  assert.equal(env.watches.length, 1, "session start creates one watcher");
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, undefined], "baseline is current");
  const state = globalThis[PROCESS_STATE];
  assert.ok(state.restartBaseline instanceof Map, "restart baseline is process-global");
  assert.ok(state.restartStale instanceof Map, "restart stale state is process-global");
  assert.ok(state.notifications instanceof Set, "notifications are process-global");
  assert.ok(state.failures instanceof Set, "failures are process-global");
  await env.shutdown();
  assert.equal(env.intervals[0].cleared, true, "shutdown clears timer");
  assert.equal(env.watches[0].closed, true, "shutdown closes watcher");
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, undefined], "shutdown clears status");
}

async function transitionsAndNotifications() {
  resetProcessState();
  const env = environment({
    "alpha.json": record("alpha", {
      reload: generation("a"),
      restart: generation("b"),
      reloadReason: "extension changed",
      restartReason: "runtime changed",
    }),
  });
  extension(env.pi);
  await env.start();

  env.records.set("beta.json", record("beta", { reload: generation("c") }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [
    STATUS_KEY,
    "warning:↻ Pi changed — /reload",
  ], "a producer first observed after startup is stale");

  env.records.set("alpha.json", record("alpha", {
    reload: generation("d"),
    restart: generation("b"),
    reloadReason: "extension changed",
  }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [
    STATUS_KEY,
    "warning:↻ Pi changed — /reload",
  ], "reload change uses warning status");
  assert.match(env.notifications.at(-1)[0], /alpha.*extension changed/, "notification names producer and reason");
  assert.equal(env.notifications.at(-1)[1], "warning", "reload notification is a warning");
  const reloadNotificationCount = env.notifications.length;
  await env.poll();
  assert.equal(env.notifications.length, reloadNotificationCount, "same generation is deduplicated");

  env.records.set("alpha.json", record("alpha", {
    reload: generation("e"),
    restart: generation("f"),
    restartReason: "runtime changed",
  }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [
    STATUS_KEY,
    "error:⟳ Pi changed — restart Pi",
  ], "restart takes precedence over reload");
  assert.equal(env.notifications.at(-1)[1], "error", "restart escalation is an error");
  assert.match(env.notifications.at(-1)[0], /alpha.*runtime changed/, "escalation explains the reason");

  const restartNotificationCount = env.notifications.length;
  env.records.set("alpha.json", record("alpha", {
    reload: generation("a"),
    restart: generation("b"),
  }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [
    STATUS_KEY,
    "error:⟳ Pi changed — restart Pi",
  ], "restart state is monotonic for the process");
  assert.equal(env.notifications.length, restartNotificationCount, "restored restart generation does not notify again");
}

async function laterClassificationUsesDeclaredSeverity() {
  resetProcessState();
  const reload = environment({ "alpha.json": record("alpha") });
  extension(reload.pi);
  await reload.start();
  reload.records.set("alpha.json", record("alpha", { reload: generation("a") }));
  await reload.poll();
  assert.deepEqual(reload.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "a reload classification first observed after startup is stale");

  resetProcessState();
  const restart = environment({ "alpha.json": record("alpha") });
  extension(restart.pi);
  await restart.start();
  restart.records.set("alpha.json", record("alpha", { restart: generation("b") }));
  await restart.poll();
  assert.deepEqual(restart.lastStatus(), [STATUS_KEY, "error:⟳ Pi changed — restart Pi"],
    "a restart classification first observed after startup is stale");
}

async function malformedStartupDoesNotCompleteBaseline() {
  resetProcessState();
  const env = environment({ "alpha.json": "{broken" });
  extension(env.pi);
  await env.start();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:Pi staleness check failed"],
    "malformed startup state reports a check failure");

  env.records.set("alpha.json", record("alpha", { reload: generation("a") }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, undefined],
    "first complete snapshot after malformed startup establishes the baseline");
}

async function validProducerChangesDuringMalformedStartup() {
  resetProcessState();
  const env = environment({
    "alpha.json": record("alpha", { reload: generation("a") }),
    "broken.json": "{broken",
  });
  extension(env.pi);
  await env.start();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:Pi staleness check failed"],
    "malformed startup state reports a check failure");

  env.records.set("alpha.json", record("alpha", { reload: generation("b") }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "a valid producer change warns while another startup record remains malformed");
  assert.match(env.notifications.at(-1)[0], /alpha/,
    "the provisional baseline change identifies the valid producer");

  env.records.set("broken.json", record("broken", { reload: generation("c") }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "snapshot recovery does not rebase a change detected from provisional state");

  env.records.set("alpha.json", record("alpha", { reload: generation("a") }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, undefined],
    "the provisional generation clears the warning after snapshot recovery");
}

async function restoredReloadAndMalformedState() {
  resetProcessState();
  const env = environment({
    "alpha.json": record("alpha", { reload: generation("a") }),
  });
  extension(env.pi);
  await env.start();
  env.records.set("alpha.json", record("alpha", { reload: generation("b") }));
  await env.poll();
  env.records.set("alpha.json", "{broken");
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "malformed state cannot hide known stale state");
  const malformedLogs = env.logs.length;
  await env.poll();
  assert.equal(env.logs.length, malformedLogs, "malformed failure logs are deduplicated");

  env.records.set("other.json", JSON.stringify({ schema: 2, producer: "other" }));
  await env.poll();
  assert.ok(env.logs.some((line) => line.includes("schema")), "unsupported schema is logged");
  env.records.set("mismatch.json", record("different", { reload: generation("c") }));
  await env.poll();
  assert.ok(env.logs.some((line) => line.includes("mismatch")), "producer mismatch is logged");
  env.records.set("bad-fields.json", JSON.stringify({
    schema: 1,
    producer: "bad-fields",
    reload: { generation: "wrong", changedAt: "yesterday", reason: "x".repeat(201) },
  }));
  await env.poll();
  assert.ok(env.logs.some((line) => /invalid|reason|generation|timestamp/.test(line)),
    "classification fields are validated");

  env.records.set("alpha.json", record("alpha", { reload: generation("a") }));
  env.records.delete("other.json");
  env.records.delete("mismatch.json");
  env.records.delete("bad-fields.json");
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, undefined], "baseline generation restores reload state");

  env.setDirectoryError("state directory missing");
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:Pi staleness check failed"],
    "missing state directory shows check failure when otherwise current");
  const missingLogs = env.logs.length;
  await env.poll();
  assert.equal(env.logs.length, missingLogs, "directory failure logs are deduplicated");
}

async function classificationRemovalPreservesKnownState() {
  resetProcessState();
  const env = environment({
    "alpha.json": record("alpha", {
      reload: generation("a"),
      restart: generation("b"),
    }),
  });
  extension(env.pi);
  await env.start();

  env.records.set("alpha.json", record("alpha", { reload: generation("c") }));
  await env.poll();
  env.records.set("alpha.json", record("alpha"));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "removing a known reload classification does not clear reload stale state");

  env.records.set("alpha.json", record("alpha", { restart: generation("d") }));
  await env.poll();
  env.records.set("alpha.json", record("alpha"));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "error:⟳ Pi changed — restart Pi"],
    "removing a known restart classification does not clear restart stale state");
}

async function missingDirectoryEnrollmentBehavior() {
  resetProcessState();
  const missing = new Error("state directory missing");
  missing.code = "ENOENT";
  const env = environment({}, { directoryError: missing });
  extension(env.pi);
  await env.start();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, undefined],
    "initial missing state directory is an empty complete snapshot");
  assert.equal(env.logs.length, 0, "initial missing state directory is not a failure");

  env.setDirectoryError(undefined);
  env.records.set("alpha.json", record("alpha", { reload: generation("a") }));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "first producer after an empty startup is stale");

  env.setDirectoryError(missing);
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "later missing directory preserves stale state");
  assert.ok(env.logs.some((line) => line.includes("state directory read failed")),
    "later missing directory follows fail-safe error handling");

  resetProcessState();
  const current = environment({
    "alpha.json": record("alpha", { reload: generation("a") }),
  });
  extension(current.pi);
  await current.start();
  current.setDirectoryError(missing);
  await current.poll();
  assert.deepEqual(current.lastStatus(), [STATUS_KEY, "warning:Pi staleness check failed"],
    "missing directory after enrollment shows check failure when current");
}

async function unreadableRecordPreservesStateAndPolling() {
  resetProcessState();
  const env = environment({
    "alpha.json": record("alpha", { reload: generation("a") }),
  }, { watchError: "watch unavailable" });
  extension(env.pi);
  await env.start();
  assert.equal(env.intervals.length, 1, "polling remains active when watcher fails");
  env.records.set("alpha.json", record("alpha", { reload: generation("b") }));
  await env.poll();
  env.records.set("alpha.json", new Error("temporarily unreadable"));
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "unreadable record preserves known stale state");
  env.records.delete("alpha.json");
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "missing record preserves known stale state");
  assert.ok(env.logs.some((line) => line.includes("known producer record missing: alpha.json")),
    "missing record is reported even when a stale warning takes precedence");
}

async function missingKnownRecordReportsFailure() {
  resetProcessState();
  const env = environment({
    "alpha.json": record("alpha", { reload: generation("a") }),
  });
  extension(env.pi);
  await env.start();

  env.records.delete("alpha.json");
  await env.poll();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:Pi staleness check failed"],
    "a missing known record reports a check failure when otherwise current");
  assert.ok(env.logs.some((line) => line.includes("known producer record missing: alpha.json")),
    "a missing known record has a distinct failure log");
  const failureCount = env.logs.length;
  await env.poll();
  assert.equal(env.logs.length, failureCount, "missing record failures are rate-limited");
}

async function watcherSchedulesEarlyPoll() {
  resetProcessState();
  const env = environment({
    "alpha.json": record("alpha", { reload: generation("a") }),
  });
  extension(env.pi);
  await env.start();
  env.records.set("alpha.json", record("alpha", { reload: generation("b") }));
  await env.watch();
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "watcher schedules an early poll");
}

async function tmuxPublicationAndFailureHandling() {
  resetProcessState();
  const previousPane = process.env.TMUX_PANE;
  process.env.TMUX_PANE = "%42";
  try {
    const env = environment({
      "alpha.json": record("alpha", { reload: generation("a"), restart: generation("b") }),
    });
    extension(env.pi);
    await env.start();
    assert.ok(env.execs.some(([command, args]) => command === "tmux"
      && args.includes("@pi_stale") && args.includes("-u")), "current state unsets tmux option");
    env.records.set("alpha.json", record("alpha", {
      reload: generation("c"), restart: generation("b"),
    }));
    await env.poll();
    assert.ok(env.execs.some(([command, args]) => command === "tmux"
      && args.includes("@pi_stale") && args.includes("reload")), "reload is published to tmux");
    assert.ok(env.execs.some(([command, args]) => command === "tmux-window-label"
      && args[0] === "%42"), "changed option refreshes window label");
    assert.ok(env.execs.some(([command, args]) => command === "tmux-remote-title"
      && args[0] === "publish"), "changed option refreshes remote title");
    env.records.set("alpha.json", record("alpha", {
      reload: generation("c"), restart: generation("d"),
    }));
    await env.poll();
    assert.ok(env.execs.some(([command, args]) => command === "tmux"
      && args.includes("@pi_stale") && args.includes("restart")), "restart is published to tmux");
    await env.shutdown();
    assert.ok(env.execs.slice(-3).some(([command, args]) => command === "tmux"
      && args.includes("-u")), "shutdown unsets tmux option");

    resetProcessState();
    const resolvedFailure = environment({
      "alpha.json": record("alpha", { reload: generation("a") }),
    }, { execResults: [
      { code: 0, killed: false, stdout: "", stderr: "" },
      {
        code: 1,
        killed: false,
        stdout: "",
        stderr: `tmux refused ${"x".repeat(1_000)}`,
      },
    ] });
    extension(resolvedFailure.pi);
    await resolvedFailure.start();
    assert.equal(resolvedFailure.execs.filter(([command]) => command === "tmux").length, 1,
      "a resolved nonzero refresh result stops publication");
    assert.equal(resolvedFailure.logs.length, 1, "a resolved tmux failure logs once");
    assert.match(resolvedFailure.logs[0], /tmux-window-label.*exit code 1.*tmux refused/,
      "a resolved tmux failure includes useful result details");
    assert.ok(Buffer.byteLength(resolvedFailure.logs[0], "utf8") <= 300,
      "a resolved tmux failure log is bounded");
    await resolvedFailure.poll();
    assert.equal(resolvedFailure.execs.filter(([command]) => command === "tmux").length, 2,
      "a resolved refresh failure retries publication on a later poll");
    assert.deepEqual(resolvedFailure.execs.slice(-2).map(([command]) => command),
      ["tmux-window-label", "tmux-remote-title"],
      "successful retry completes both refresh commands");
    const resolvedFailureLogCount = resolvedFailure.logs.length;
    await resolvedFailure.poll();
    assert.equal(resolvedFailure.logs.length, resolvedFailureLogCount,
      "resolved tmux failures remain rate-limited after recovery");
    assert.equal(resolvedFailure.execs.filter(([command]) => command === "tmux").length, 2,
      "successful retry caches publication only after all commands succeed");

    resetProcessState();
    const failing = environment({
      "alpha.json": record("alpha", { reload: generation("a") }),
    }, { execError: "tmux failed" });
    extension(failing.pi);
    await failing.start();
    const failureCount = failing.logs.length;
    await failing.poll();
    assert.equal(failing.logs.length, failureCount, "tmux failures are rate-limited");
  } finally {
    if (previousPane === undefined) delete process.env.TMUX_PANE;
    else process.env.TMUX_PANE = previousPane;
  }
}

async function mixedReplacementRetainsReloadState() {
  resetProcessState();
  const first = environment({
    "alpha.json": record("alpha", { reload: generation("a") }),
  });
  extension(first.pi);
  await first.start();
  first.records.set("alpha.json", record("alpha", { reload: generation("b") }));
  await first.poll();
  await first.shutdown();

  const second = environment({
    "alpha.json": record("alpha", { reload: generation("b") }),
    "broken.json": "{broken",
  });
  extension(second.pi);
  await second.start();
  assert.deepEqual(second.lastStatus(), [STATUS_KEY, "warning:↻ Pi changed — /reload"],
    "mixed replacement snapshot retains the previous reload baseline and warning");
}

async function replacementBaselinesAndProcessPersistence() {
  resetProcessState();
  const first = environment({
    "alpha.json": record("alpha", { reload: generation("a"), restart: generation("b") }),
  });
  extension(first.pi);
  await first.start();
  first.records.set("alpha.json", record("alpha", {
    reload: generation("c"), restart: generation("d"),
  }));
  await first.poll();
  await first.shutdown();

  const second = environment({
    "alpha.json": record("alpha", { reload: generation("c"), restart: generation("d") }),
  });
  extension(second.pi);
  await second.start();
  assert.deepEqual(second.lastStatus(), [STATUS_KEY, "error:⟳ Pi changed — restart Pi"],
    "replacement resets reload baseline but preserves process restart stale state");
  assert.equal(globalThis[PROCESS_STATE].restartBaseline.get("alpha"), generation("b"),
    "replacement reuses original restart baseline");
  const before = second.notifications.length;
  await second.poll();
  assert.equal(second.notifications.length, before, "replacement deduplicates process notifications");
}

await startupBaselineAndLifecycle();
await transitionsAndNotifications();
await laterClassificationUsesDeclaredSeverity();
await malformedStartupDoesNotCompleteBaseline();
await validProducerChangesDuringMalformedStartup();
await restoredReloadAndMalformedState();
await classificationRemovalPreservesKnownState();
await missingDirectoryEnrollmentBehavior();
await tmuxPublicationAndFailureHandling();
await unreadableRecordPreservesStateAndPolling();
await missingKnownRecordReportsFailure();
await watcherSchedulesEarlyPoll();
await mixedReplacementRetainsReloadState();
await replacementBaselinesAndProcessPersistence();
delete globalThis[ADAPTERS];
console.log("Pi session staleness extension behavior passed");
JAVASCRIPT
