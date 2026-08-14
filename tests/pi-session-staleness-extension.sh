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

  globalThis[ADAPTERS] = {
    stateDirectory: "/state/producers",
    async readDirectory() {
      if (directoryError) throw new Error(directoryError);
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
      return { code: 0, stdout: "", stderr: "" };
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
  assert.deepEqual(env.lastStatus(), [STATUS_KEY, undefined], "later producer enrollment gets a baseline");

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
await restoredReloadAndMalformedState();
await unreadableRecordPreservesStateAndPolling();
await watcherSchedulesEarlyPoll();
await tmuxPublicationAndFailureHandling();
await replacementBaselinesAndProcessPersistence();
delete globalThis[ADAPTERS];
console.log("Pi session staleness extension behavior passed");
JAVASCRIPT
