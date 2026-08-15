import { promises as fileSystem, watch as watchFileSystem } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const ADAPTERS_SYMBOL = Symbol.for("nmb.pi-session-staleness.adapters");
const PROCESS_STATE_SYMBOL = Symbol.for("nmb.pi-session-staleness.process-state");
const RELOAD_STATE_SYMBOL = Symbol.for("nmb.pi-session-staleness.reload-state");
const STATUS_KEY = "pi-session-staleness";
const POLL_INTERVAL_MS = 10_000;
const PRODUCER_PATTERN = /^[a-z0-9][a-z0-9-]{0,63}$/;
const GENERATION_PATTERN = /^sha256:[0-9a-f]{64}$/;
const MAX_REASON_BYTES = 200;
const CLASSIFICATIONS = ["reload", "restart"];

function defaultStateDirectory() {
  const stateRoot = process.env.XDG_STATE_HOME
    || join(process.env.HOME || homedir(), ".local", "state");
  return join(stateRoot, "pi-session-staleness", "v1", "producers");
}

function createAdapters(pi) {
  const injected = globalThis[ADAPTERS_SYMBOL];
  if (injected) return injected;

  return {
    stateDirectory: defaultStateDirectory(),
    readDirectory: (path) => fileSystem.readdir(path),
    readFile: (path) => fileSystem.readFile(path, "utf8"),
    watchDirectory: (path, callback) => watchFileSystem(path, callback),
    setInterval: (callback, milliseconds) => setInterval(callback, milliseconds),
    clearInterval: (timer) => clearInterval(timer),
    log: (message) => console.error(message),
    exec: (command, args) => pi.exec(command, args),
  };
}

function processState() {
  const existing = globalThis[PROCESS_STATE_SYMBOL];
  if (existing) return existing;

  const created = {
    restartBaseline: new Map(),
    restartStale: new Map(),
    notifications: new Set(),
    failures: new Set(),
  };
  globalThis[PROCESS_STATE_SYMBOL] = created;
  return created;
}

function objectWithExactKeys(value, requiredKeys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const keys = Object.keys(value).sort();
  return keys.length === requiredKeys.length
    && keys.every((key, index) => key === [...requiredKeys].sort()[index]);
}

function validTimestamp(value) {
  if (typeof value !== "string") return false;
  const date = new Date(value);
  return !Number.isNaN(date.valueOf()) && date.toISOString() === value;
}

function parseRecord(fileName, content) {
  if (typeof fileName !== "string" || !fileName.endsWith(".json")) {
    throw new Error(`invalid producer record name: ${fileName}`);
  }
  const fileProducer = fileName.slice(0, -5);
  if (!PRODUCER_PATTERN.test(fileProducer)) {
    throw new Error(`invalid producer record name: ${fileName}`);
  }

  let record;
  try {
    record = JSON.parse(content);
  } catch (error) {
    throw new Error(`invalid JSON in ${fileName}: ${error.message}`);
  }

  if (!record || typeof record !== "object" || Array.isArray(record)) {
    throw new Error(`invalid producer record object: ${fileName}`);
  }
  const allowedKeys = new Set(["schema", "producer", ...CLASSIFICATIONS]);
  if (Object.keys(record).some((key) => !allowedKeys.has(key))) {
    throw new Error(`invalid producer record keys: ${fileName}`);
  }
  if (record.schema !== 1) {
    throw new Error(`unsupported producer record schema: ${fileName}`);
  }
  if (record.producer !== fileProducer || !PRODUCER_PATTERN.test(record.producer)) {
    throw new Error(`producer mismatch: ${fileName}`);
  }

  for (const classification of CLASSIFICATIONS) {
    if (!Object.hasOwn(record, classification)) continue;
    const entry = record[classification];
    if (!objectWithExactKeys(entry, ["generation", "changedAt", "reason"])) {
      throw new Error(`invalid ${classification} classification: ${fileName}`);
    }
    if (!GENERATION_PATTERN.test(entry.generation)) {
      throw new Error(`invalid ${classification} generation: ${fileName}`);
    }
    if (!validTimestamp(entry.changedAt)) {
      throw new Error(`invalid ${classification} timestamp: ${fileName}`);
    }
    if (typeof entry.reason !== "string" || entry.reason.length === 0
      || Buffer.byteLength(entry.reason, "utf8") > MAX_REASON_BYTES) {
      throw new Error(`invalid ${classification} reason: ${fileName}`);
    }
  }

  return record;
}

export default function piSessionStaleness(pi) {
  const adapters = createAdapters(pi);
  const shared = processState();
  const previousReloadState = globalThis[RELOAD_STATE_SYMBOL];
  const reloadBaseline = new Map(previousReloadState?.reloadBaseline);
  const knownRecords = new Map(previousReloadState?.knownRecords);
  let baselineComplete = previousReloadState?.baselineComplete ?? false;
  let hasEnrolledProducer = previousReloadState?.hasEnrolledProducer ?? false;
  let startupSnapshot = true;
  let timer;
  let watcher;
  let context;
  let running = false;
  let pollPromise;
  let tmuxPublished = Symbol("unpublished");

  function reportFailure(message) {
    const normalized = `pi-session-staleness: ${message}`;
    if (shared.failures.has(normalized)) return;
    shared.failures.add(normalized);
    try {
      adapters.log(normalized);
    } catch {
      // Logging must not make Pi unusable.
    }
  }

  function notify(producer, classification, entry) {
    const key = `${producer}\0${classification}\0${entry.generation}`;
    if (shared.notifications.has(key)) return;
    shared.notifications.add(key);
    try {
      context?.ui.notify(
        `Pi changed (${producer}): ${entry.reason}`,
        classification === "restart" ? "error" : "warning",
      );
    } catch (error) {
      reportFailure(`notification failed: ${error.message}`);
    }
  }

  function saveReloadState() {
    globalThis[RELOAD_STATE_SYMBOL] = {
      reloadBaseline: new Map(reloadBaseline),
      knownRecords: new Map(knownRecords),
      baselineComplete,
      hasEnrolledProducer,
    };
  }

  function mergeRecord(record) {
    const previous = knownRecords.get(record.producer);
    const merged = { ...record };
    for (const classification of CLASSIFICATIONS) {
      if (!Object.hasOwn(record, classification) && previous?.[classification]) {
        merged[classification] = previous[classification];
      }
    }
    knownRecords.set(record.producer, merged);
    hasEnrolledProducer = true;
    return merged;
  }

  function observeRecord(record) {
    const producer = record.producer;
    mergeRecord(record);

    if (record.reload) {
      if (!reloadBaseline.has(producer)
        || record.reload.generation !== reloadBaseline.get(producer)) {
        notify(producer, "reload", record.reload);
      }
    }

    if (record.restart) {
      if (!shared.restartBaseline.has(producer)
        || record.restart.generation !== shared.restartBaseline.get(producer)) {
        shared.restartStale.set(producer, record.restart);
        notify(producer, "restart", record.restart);
      }
    }
  }

  function observeStartupSnapshot(records) {
    for (const record of records.values()) {
      const merged = mergeRecord(record);
      if (record.reload && !reloadBaseline.has(record.producer)) {
        reloadBaseline.set(record.producer, merged.reload.generation);
      }
      if (record.restart && !shared.restartBaseline.has(record.producer)) {
        shared.restartBaseline.set(record.producer, merged.restart.generation);
      }
      observeRecord(record);
    }
  }

  function replaceReloadBaseline(records) {
    for (const record of records.values()) {
      const merged = mergeRecord(record);
      if (record.reload) reloadBaseline.set(record.producer, merged.reload.generation);
      if (record.restart) {
        if (!shared.restartBaseline.has(record.producer)) {
          shared.restartStale.set(record.producer, record.restart);
          notify(record.producer, "restart", record.restart);
        } else if (record.restart.generation
          !== shared.restartBaseline.get(record.producer)) {
          shared.restartStale.set(record.producer, record.restart);
          notify(record.producer, "restart", record.restart);
        }
      }
    }
  }

  function currentSeverity() {
    if (shared.restartStale.size > 0) return "restart";
    for (const [producer, record] of knownRecords) {
      if (record.reload
        && (!reloadBaseline.has(producer)
          || record.reload.generation !== reloadBaseline.get(producer))) {
        return "reload";
      }
    }
    return undefined;
  }

  function publishStatus(severity, failed) {
    if (!context) return;
    let value;
    if (severity === "restart") {
      value = context.ui.theme.fg("error", "⟳ Pi changed — restart Pi");
    } else if (severity === "reload") {
      value = context.ui.theme.fg("warning", "↻ Pi changed — /reload");
    } else if (failed) {
      value = context.ui.theme.fg("warning", "Pi staleness check failed");
    }
    try {
      context.ui.setStatus(STATUS_KEY, value);
    } catch (error) {
      reportFailure(`status publication failed: ${error.message}`);
    }
  }

  async function refreshTmux() {
    const pane = process.env.TMUX_PANE;
    if (!pane) return;
    for (const [command, args] of [
      ["tmux-window-label", [pane]],
      ["tmux-remote-title", ["publish"]],
    ]) {
      try {
        await adapters.exec(command, args);
      } catch (error) {
        reportFailure(`${command} failed: ${error.message}`);
      }
    }
  }

  async function publishTmux(severity, force = false) {
    const pane = process.env.TMUX_PANE;
    if (!pane || (!force && tmuxPublished === severity)) return;

    const args = severity
      ? ["set-option", "-p", "-t", pane, "@pi_stale", severity]
      : ["set-option", "-p", "-u", "-t", pane, "@pi_stale"];
    try {
      await adapters.exec("tmux", args);
      tmuxPublished = severity;
      await refreshTmux();
    } catch (error) {
      reportFailure(`tmux publication failed: ${error.message}`);
    }
  }

  async function poll() {
    let failed = false;
    let fileNames;
    try {
      fileNames = await adapters.readDirectory(adapters.stateDirectory);
      if (!Array.isArray(fileNames)) throw new Error("directory result is not an array");
    } catch (error) {
      if (error?.code === "ENOENT" && !hasEnrolledProducer) {
        baselineComplete = true;
        startupSnapshot = false;
        saveReloadState();
        publishStatus(undefined, false);
        await publishTmux(undefined);
        return;
      }
      failed = true;
      startupSnapshot = false;
      reportFailure(`state directory read failed: ${error.message}`);
      const severity = currentSeverity();
      publishStatus(severity, failed);
      await publishTmux(severity);
      return;
    }

    const snapshot = new Map();
    for (const fileName of [...fileNames].sort()) {
      if (typeof fileName !== "string" || !fileName.endsWith(".json")) continue;
      try {
        const content = await adapters.readFile(join(adapters.stateDirectory, fileName));
        const record = parseRecord(fileName, content);
        snapshot.set(record.producer, record);
      } catch (error) {
        failed = true;
        reportFailure(`record read failed for ${fileName}: ${error.message}`);
      }
    }

    if (!baselineComplete) {
      observeStartupSnapshot(snapshot);
      if (!failed) baselineComplete = true;
    } else if (startupSnapshot && !failed) {
      replaceReloadBaseline(snapshot);
    } else {
      for (const record of snapshot.values()) observeRecord(record);
    }
    startupSnapshot = false;
    saveReloadState();

    const severity = currentSeverity();
    publishStatus(severity, failed);
    await publishTmux(severity);
  }

  function requestPoll() {
    if (!running) return Promise.resolve();
    if (pollPromise) return pollPromise;
    pollPromise = poll()
      .catch((error) => reportFailure(`poll failed: ${error.message}`))
      .finally(() => { pollPromise = undefined; });
    return pollPromise;
  }

  function startWatcher() {
    try {
      watcher = adapters.watchDirectory(adapters.stateDirectory, () => {
        void requestPoll();
      });
      if (watcher && typeof watcher.on === "function") {
        watcher.on("error", (error) => {
          reportFailure(`directory watch failed: ${error.message}`);
          try {
            watcher.close();
          } catch {
            // Polling remains active if watcher cleanup fails.
          }
          watcher = undefined;
        });
      }
    } catch (error) {
      reportFailure(`directory watch failed: ${error.message}`);
    }
  }

  pi.on("session_start", async (_event, ctx) => {
    if (running) return;
    running = true;
    context = ctx;
    await requestPoll();
    if (!running) return;
    timer = adapters.setInterval(() => requestPoll(), POLL_INTERVAL_MS);
    startWatcher();
  });

  pi.on("session_shutdown", async () => {
    if (!running) return;
    running = false;
    if (timer !== undefined) {
      try {
        adapters.clearInterval(timer);
      } catch (error) {
        reportFailure(`timer cleanup failed: ${error.message}`);
      }
      timer = undefined;
    }
    if (watcher) {
      try {
        watcher.close();
      } catch (error) {
        reportFailure(`watch cleanup failed: ${error.message}`);
      }
      watcher = undefined;
    }
    if (pollPromise) await pollPromise;
    try {
      context?.ui.setStatus(STATUS_KEY, undefined);
    } catch (error) {
      reportFailure(`status cleanup failed: ${error.message}`);
    }
    await publishTmux(undefined, true);
    context = undefined;
  });
}
