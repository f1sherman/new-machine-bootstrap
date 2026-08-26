#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
EXTENSION="$REPO_ROOT/roles/common/files/pi/extensions/managed-hooks.ts"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
cp "$EXTENSION" "$TMPROOT/managed-hooks.mjs"
mkdir -p "$TMPROOT/worktree/docs/superpowers/specs"
: >"$TMPROOT/worktree/docs/superpowers/specs/design.md"

node_cmd=(node)
if ! command -v node >/dev/null 2>&1; then
  mise_bin="${MISE_BIN:-$HOME/.local/bin/mise}"
  node_version="$(yq -r '.tool_versions.runtimes.node' "$REPO_ROOT/vars/tool_versions.yml")"
  node_cmd=("$mise_bin" exec "node@$node_version" -- node)
fi

cat >"$TMPROOT/check.mjs" <<'NODE'
import assert from "node:assert/strict";
import path from "node:path";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const worktreeRoot = process.env.PI_HOOK_TEST_WORKTREE;
const asrCommand = path.join(process.env.HOME, ".local", "bin", "asr");
const handlers = new Map();
const calls = [];
const sessionNames = [];
const registeredToolNames = [];
const warnings = [];
console.warn = (...args) => warnings.push(args);
let sessionNameTool;
let sessionNameError;
let doneSessionTool;
let shutdownCalls = 0;
let sessionDoneResultQueue = [];
let currentSessionName = "";
let activeSessionFile = "/sessions/current.jsonl";
let activeSessionId = "019fe7a6-a219-7548-a6ef-1f23885864f4";
let asrResultQueue = [];
let herdrWorkspaceResultQueue = [];
let branch = "main";
let taskStatus = "";
let goalChildDeferred;
let goalChildIgnoresAbort = false;
let goalChildResultQueue = [];
let publishedIdentity = { source: "", subject: "" };
let fallbackRestores = 0;
let sessionContextIsStale = false;
let staleContextReads = 0;
const failedGitRootCwds = new Set();
const failedBranchCwds = new Set();

const ok = (stdout = "") => ({ stdout, stderr: "", code: 0, killed: false });
const fail = () => ({ stdout: "", stderr: "", code: 1, killed: false });

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

async function flushAsyncWork() {
  for (let index = 0; index < 8; index += 1) {
    await new Promise((resolve) => setImmediate(resolve));
  }
}

async function withStdoutTTY(callback) {
  const descriptor = Object.getOwnPropertyDescriptor(process.stdout, "isTTY");
  Object.defineProperty(process.stdout, "isTTY", { configurable: true, value: true });
  try {
    return await callback();
  } finally {
    if (descriptor) Object.defineProperty(process.stdout, "isTTY", descriptor);
    else delete process.stdout.isTTY;
  }
}

function isGoalChild(args) {
  return args.at(-1).startsWith("New session prompt: ");
}

function isSubjectChild(args) {
  const index = args.indexOf("--system-prompt");
  return index !== -1 && args[index + 1].includes("user's task");
}

function abortable(promise, signal) {
  if (signal?.aborted) return Promise.resolve({ ...fail(), killed: true });
  return new Promise((resolve) => {
    const abort = () => resolve({ ...fail(), killed: true });
    signal?.addEventListener("abort", abort, { once: true });
    promise.then((result) => {
      signal?.removeEventListener("abort", abort);
      resolve(result);
    });
  });
}

const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
  registerTool(definition) {
    registeredToolNames.push(definition.name);
    if (definition.name === "set_session_name") sessionNameTool = definition;
    if (definition.name === "done_session") doneSessionTool = definition;
  },
  setSessionName(name) {
    if (sessionNameError) throw sessionNameError;
    currentSessionName = name;
    sessionNames.push(name);
  },
  async exec(command, args, options = {}) {
    calls.push({ command, args });
    if (command === "/usr/bin/env" && args.at(-1) === "pi-session-done") {
      const queued = sessionDoneResultQueue.shift();
      if (queued instanceof Error) throw queued;
      if (queued?.promise) return queued.promise;
      return queued || ok();
    }
    if (command === asrCommand) {
      const queued = asrResultQueue.shift();
      if (queued instanceof Error) throw queued;
      if (queued?.promise) return queued.promise;
      return queued || ok();
    }
    if (command === "herdr" && args[0] === "workspace" && args[1] === "get") {
      const queued = herdrWorkspaceResultQueue.shift();
      if (queued instanceof Error) throw queued;
      if (queued?.promise) return queued.promise;
      return queued || fail();
    }
    if (command === "herdr") return ok();
    if (command === "tmux" && args[0] === "show-options") {
      if (args.at(-1) === "@agent_worktree_path") return ok(`${worktreeRoot}\n`);
      if (args.at(-1) === "@window-label") return ok("pi main-repo\n");
      return fail();
    }
    if (command === "tmux" && args[0] === "set-option") return ok();
    if (command === "tmux-agent-state" && args[0] === "set-identity") {
      publishedIdentity = { source: args[1], subject: args[2] };
      taskStatus = `active\t${args[1]}\t${args[2]}`;
      return ok();
    }
    if (command === "tmux-agent-state" && args[0] === "status") {
      return taskStatus ? ok(`${taskStatus}\n`) : fail();
    }
    if (command === "tmux-agent-state" && args[0] === "clear-task") {
      taskStatus = "";
      publishedIdentity = { source: "", subject: "" };
      return ok();
    }
    if (command === "tmux-agent-worktree" && args[0] === "sync-current") {
      fallbackRestores += 1;
      return ok();
    }
    if (command === "tmux-agent-state" || command.startsWith("tmux-")) return ok();
    if (command === "pi" && isGoalChild(args)) {
      const queued = goalChildResultQueue.shift();
      if (queued instanceof Error) throw queued;
      if (queued) return queued;
      if (!goalChildDeferred) return ok("generated goal\n");
      return goalChildIgnoresAbort
        ? goalChildDeferred.promise
        : abortable(goalChildDeferred.promise, options.signal);
    }
    if (command === "pi" && isSubjectChild(args)) return ok("nested process subject\n");
    if (command === "git" && args.includes("rev-parse")) {
      const dynamic = ["$", "`", "*", "?", "[", "]", "{", "}", "\\"];
      if (args.some((arg) => failedGitRootCwds.has(String(arg))
        || String(arg).startsWith("/missing")
        || dynamic.some((character) => String(arg).includes(character)))) return fail();
      const featureRoots = [worktreeRoot, "/repo/-", "/repo/~+", "/repo/~-", "/repo/feature-repo"];
      return ok(args.some((arg) => featureRoots.some((root) => String(arg).startsWith(root)))
        ? `${worktreeRoot}\n`
        : "/repo\n");
    }
    if (command === "git" && args.includes("branch")) {
      if (args.some((arg) => failedBranchCwds.has(String(arg)))) return fail();
      return ok(args.includes(worktreeRoot) ? "feature\n" : `${branch}\n`);
    }
    return fail();
  },
};

const ctx = {
  cwd: "/repo",
  signal: new AbortController().signal,
  shutdown() {
    shutdownCalls += 1;
  },
  ui: {
    theme: { fg(_color, value) { return value; } },
    setStatus() {},
  },
  sessionManager: new Proxy({
    getSessionName() { return currentSessionName; },
    getSessionFile() { return activeSessionFile; },
    getSessionId() { return activeSessionId; },
  }, {
    get(target, property) {
      if (sessionContextIsStale) {
        staleContextReads += 1;
        throw new Error("stale extension context");
      }
      return target[property];
    },
  }),
};

process.env.TMUX = "1";
process.env.TMUX_PANE = "%1";
const { default: install } = await import(pathToFileURL(extensionPath));
install(pi);

const registryCalls = () => calls.filter((call) => call.command === asrCommand);
const clearCalls = () => { calls.length = 0; };

const savedTmux = process.env.TMUX;
const savedTmuxPane = process.env.TMUX_PANE;
delete process.env.TMUX;
delete process.env.TMUX_PANE;
currentSessionName = "restored registry name";
clearCalls();
await handlers.get("session_start")({}, ctx);
await flushAsyncWork();
assert.deepEqual(registryCalls(), [{
  command: asrCommand,
  args: [
    "register", "--source", "pi", "--session-id", activeSessionId,
    "--local", "--status", "active",
    "--name", "restored registry name", "--cwd", "/repo",
    "--adapter", "pi-local",
    "--adapter-config", JSON.stringify({ session_file: activeSessionFile }),
  ],
}], "persistent session start publishes the name-only registry record");
assert.equal(registryCalls()[0].args.includes("--goal"), false,
  "registry registration does not publish separate goal state");

activeSessionFile = "";
clearCalls();
await handlers.get("session_start")({}, ctx);
await flushAsyncWork();
assert.equal(registryCalls().length, 0, "ephemeral session start is not registered");
activeSessionFile = "/sessions/current.jsonl";
activeSessionId = "";
clearCalls();
await handlers.get("session_start")({}, ctx);
await flushAsyncWork();
assert.equal(registryCalls().length, 0,
  "session start without a native session ID is not registered");
activeSessionId = "019fe7a6-a219-7548-a6ef-1f23885864f4";

clearCalls();
currentSessionName = "registry name outside tmux";
await handlers.get("session_info_changed")({ name: currentSessionName }, ctx);
await flushAsyncWork();
assert.deepEqual(registryCalls(), [{
  command: asrCommand,
  args: [
    "update", "--source", "pi", "--session-id", activeSessionId,
    "--name", "registry name outside tmux",
  ],
}], "session name changes publish outside tmux");

process.env.HERDR_ENV = "1";
process.env.HERDR_TAB_ID = "w1:t2";
process.env.HERDR_WORKSPACE_ID = "w1";
const workspaceResult = (tabCount) => ok(JSON.stringify({
  id: "cli:workspace:get",
  result: { workspace: { workspace_id: "w1", tab_count: tabCount } },
}));
const herdrCalls = () => calls.filter((call) => call.command === "herdr");

clearCalls();
herdrWorkspaceResultQueue.push(workspaceResult(1));
currentSessionName = "renamed Herdr session";
await withStdoutTTY(() => handlers.get("session_info_changed")({
  name: currentSessionName,
}, ctx));
assert.deepEqual(herdrCalls(), [{
  command: "herdr",
  args: ["tab", "rename", "w1:t2", "renamed Herdr session"],
}, {
  command: "herdr",
  args: ["workspace", "get", "w1"],
}, {
  command: "herdr",
  args: ["workspace", "rename", "w1", "renamed Herdr session"],
}], "session name changes rename a single-tab Herdr workspace and its tab");

clearCalls();
herdrWorkspaceResultQueue.push(workspaceResult(1));
currentSessionName = "";
await withStdoutTTY(() => handlers.get("session_info_changed")({ name: "" }, ctx));
assert.deepEqual(herdrCalls(), [{
  command: "herdr",
  args: ["tab", "rename", "w1:t2", ""],
}, {
  command: "herdr",
  args: ["workspace", "get", "w1"],
}, {
  command: "herdr",
  args: ["workspace", "rename", "w1", ""],
}], "clearing a session name clears a single-tab Herdr workspace and its tab");

clearCalls();
herdrWorkspaceResultQueue.push(workspaceResult(2));
currentSessionName = "shared workspace tab";
await withStdoutTTY(() => handlers.get("session_info_changed")({
  name: currentSessionName,
}, ctx));
assert.deepEqual(herdrCalls(), [{
  command: "herdr",
  args: ["tab", "rename", "w1:t2", "shared workspace tab"],
}, {
  command: "herdr",
  args: ["workspace", "get", "w1"],
}], "session name changes preserve a multi-tab Herdr workspace name");

for (const lookupResult of [fail(), ok("not json")]) {
  clearCalls();
  herdrWorkspaceResultQueue.push(lookupResult);
  currentSessionName = "lookup unavailable";
  await withStdoutTTY(() => handlers.get("session_info_changed")({
    name: currentSessionName,
  }, ctx));
  assert.deepEqual(herdrCalls(), [{
    command: "herdr",
    args: ["tab", "rename", "w1:t2", "lookup unavailable"],
  }, {
    command: "herdr",
    args: ["workspace", "get", "w1"],
  }], "workspace lookup failures do not block Herdr tab renames");
}
delete process.env.HERDR_ENV;
delete process.env.HERDR_TAB_ID;
delete process.env.HERDR_WORKSPACE_ID;

clearCalls();
const firstDelayedRegistryUpdate = deferred();
const secondDelayedRegistryUpdate = deferred();
asrResultQueue.push(firstDelayedRegistryUpdate, secondDelayedRegistryUpdate);
const firstRegistryUpdate = handlers.get("session_info_changed")({
  name: "first registry name",
}, ctx);
await flushAsyncWork();
const secondRegistryUpdate = handlers.get("session_info_changed")({
  name: "second registry name",
}, ctx);
await Promise.all([firstRegistryUpdate, secondRegistryUpdate]);
await flushAsyncWork();
assert.deepEqual(registryCalls().map((call) => call.args.at(-1)), [
  "first registry name",
], "registry name updates wait for earlier publication");
firstDelayedRegistryUpdate.resolve(ok());
await flushAsyncWork();
assert.deepEqual(registryCalls().map((call) => call.args.at(-1)), [
  "first registry name",
  "second registry name",
], "serialized registry updates leave the newest name last");
secondDelayedRegistryUpdate.resolve(ok());
await flushAsyncWork();

clearCalls();
const delayedRegistryStart = deferred();
asrResultQueue.push(delayedRegistryStart);
let delayedStartSettled = false;
const delayedStart = handlers.get("session_start")({}, ctx).then(() => {
  delayedStartSettled = true;
});
await flushAsyncWork();
assert.equal(delayedStartSettled, true,
  "session start continues while registry registration is pending");
delayedRegistryStart.resolve(ok());
await delayedStart;
await flushAsyncWork();

clearCalls();
const delayedRegistrationBeforeDone = deferred();
asrResultQueue.push(delayedRegistrationBeforeDone);
await handlers.get("session_start")({}, ctx);
await flushAsyncWork();
sessionDoneResultQueue.push(ok("Marked source session current done.\n"));
let doneSettled = false;
const doneResultPromise = doneSessionTool.execute(
  "done-session",
  {},
  ctx.signal,
  undefined,
  ctx,
).then((result) => {
  doneSettled = true;
  return result;
});
await flushAsyncWork();
assert.equal(doneSettled, false,
  "done_session waits for pending registry registration");
delayedRegistrationBeforeDone.resolve(ok());
const doneResult = await doneResultPromise;
assert.equal(shutdownCalls, 1,
  "successful completion requests graceful shutdown once");
assert.equal(doneResult.terminate, true,
  "successful completion stops the follow-up model turn");
const sessionDoneCalls = calls.filter((call) => (
  call.command === "/usr/bin/env" && call.args.at(-1) === "pi-session-done"
));
assert.equal(sessionDoneCalls.length, 1,
  "done_session invokes the completion helper exactly once");
assert.deepEqual(sessionDoneCalls[0], {
  command: "/usr/bin/env",
  args: [
    `PI_SESSION_ID=${activeSessionId}`,
    `PI_SESSION_FILE=${activeSessionFile}`,
    "pi-session-done",
  ],
}, "done_session passes the current identity without a shell");

shutdownCalls = 0;
sessionDoneResultQueue.push({
  stdout: "Source session is done, but laptop synchronization failed.\n",
  stderr: "ASR synchronization failed after helper completion.\n",
  code: 3,
  killed: false,
});
await assert.rejects(
  doneSessionTool.execute("done-sync-failed", {}, ctx.signal, undefined, ctx),
  (error) => {
    assert.match(error.message, /laptop synchronization failed/);
    assert.match(error.message, /ASR synchronization failed/);
    return true;
  },
);
assert.equal(shutdownCalls, 0,
  "synchronization failure keeps Pi open");

sessionDoneResultQueue.push({ stdout: "", stderr: "failed", code: 1, killed: false });
await assert.rejects(
  doneSessionTool.execute("done-failed", {}, ctx.signal, undefined, ctx),
  /failed/,
);
assert.equal(shutdownCalls, 0, "ordinary failure keeps Pi open");

sessionDoneResultQueue.push({ stdout: "", stderr: "", code: 0, killed: true });
await assert.rejects(
  doneSessionTool.execute("done-killed", {}, ctx.signal, undefined, ctx),
  /cancelled/,
);
assert.equal(shutdownCalls, 0, "cancelled completion keeps Pi open");

const persistentSessionId = activeSessionId;
activeSessionId = "";
clearCalls();
await assert.rejects(
  doneSessionTool.execute("done-ephemeral", {}, ctx.signal, undefined, ctx),
  /not persistent/,
);
assert.equal(calls.some((call) => call.command === "/usr/bin/env"), false,
  "completion without a persistent identity does not invoke the helper");
assert.equal(shutdownCalls, 0,
  "completion without a persistent identity keeps Pi open");
activeSessionId = persistentSessionId;

process.env.TMUX = savedTmux;
process.env.TMUX_PANE = savedTmuxPane;
clearCalls();
const delayedRegistryName = deferred();
asrResultQueue.push(delayedRegistryName);
currentSessionName = "name completes before registry";
publishedIdentity = { source: "", subject: "" };
let delayedNameSettled = false;
const delayedName = withStdoutTTY(
  () => handlers.get("session_info_changed")({ name: currentSessionName }, ctx),
).then(() => {
  delayedNameSettled = true;
});
await flushAsyncWork();
assert.equal(delayedNameSettled, true,
  "session name synchronization continues while registry publication is pending");
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "name completes before registry",
}, "tmux name synchronization completes while registry publication is pending");
delayedRegistryName.resolve(ok());
await delayedName;
await flushAsyncWork();

clearCalls();
asrResultQueue.push(fail());
await assert.doesNotReject(
  handlers.get("session_start")({}, ctx),
  "nonzero registry registration does not reject session start",
);
await flushAsyncWork();
asrResultQueue.push(new Error("registry unavailable"));
await assert.doesNotReject(
  handlers.get("session_info_changed")({ name: currentSessionName }, ctx),
  "thrown registry update does not reject session name synchronization",
);
await flushAsyncWork();

clearCalls();
await handlers.get("session_tree")({}, ctx);
await flushAsyncWork();
assert.equal(registryCalls().length, 0,
  "session tree changes do not publish separate registry state");
await handlers.get("session_shutdown")({}, ctx);
await flushAsyncWork();
assert.equal(registryCalls().some((call) => call.args[0] === "done"), false,
  "session shutdown never marks a registry record done");

currentSessionName = "";
taskStatus = "";
publishedIdentity = { source: "", subject: "" };
clearCalls();

currentSessionName = "";
publishedIdentity = { source: "", subject: "" };
await handlers.get("session_start")({ reason: "resume" }, ctx);
assert.deepEqual(publishedIdentity, { source: "", subject: "" },
  "an unnamed resumed session does not replace the tmux fallback");
assert.equal(calls.some((call) => call.command === "tmux-update-pane-label"
  || call.command === "tmux-window-label"
  || (call.command === "tmux-agent-state" && call.args[0] === "set-kind")), false,
  "non-TTY session_start does not mutate tmux state");

currentSessionName = "";
taskStatus = "active\tmanual\tstale resume name";
publishedIdentity = { source: "manual", subject: "stale resume name" };
const resumeFallbacks = fallbackRestores;
await withStdoutTTY(() => handlers.get("session_start")({ reason: "resume" }, ctx));
assert.deepEqual(publishedIdentity, { source: "", subject: "" },
  "an unnamed resume clears a stale manual Pi identity");
assert.equal(fallbackRestores, resumeFallbacks + 1,
  "an unnamed resume restores worktree fallback state");

currentSessionName = "restored session name";
await withStdoutTTY(() => handlers.get("session_start")({ reason: "resume" }, ctx));
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "restored session name",
}, "same-pane resume publishes the restored Pi session name");

const renameResult = await withStdoutTTY(() => sessionNameTool.execute(
  "rename-session",
  { name: "new broad name" },
  ctx.signal,
  undefined,
  ctx,
));
assert.equal(currentSessionName, "new broad name");
assert.deepEqual(renameResult.details, { name: "new broad name" });
assert.equal(registeredToolNames.includes("set_session_goal"), false,
  "the extension does not register the old goal tool alias");
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "new broad name",
});
assert.equal(calls.some((call) => call.command === "tmux"
  && call.args.includes("@pi_managed_session_name")), false,
  "single-name flow does not use the old tmux ownership marker");

currentSessionName = "";
const clearTaskCallsBeforeNameClear = calls.filter((call) =>
  call.command === "tmux-agent-state" && call.args[0] === "clear-task").length;
const fallbacksBeforeNameClear = fallbackRestores;
await withStdoutTTY(() => handlers.get("session_info_changed")({ name: "" }, ctx));
assert.equal(calls.filter((call) => call.command === "tmux-agent-state"
  && call.args[0] === "clear-task").length, clearTaskCallsBeforeNameClear + 1,
  "clearing a manual Pi name clears the published task once");
assert.equal(fallbackRestores, fallbacksBeforeNameClear + 1,
  "clearing a manual Pi name restores worktree fallback state once");
assert.deepEqual(publishedIdentity, { source: "", subject: "" },
  "clearing a manual Pi name removes the published identity");

currentSessionName = "";
taskStatus = "active\tmanual\tstale tree name";
publishedIdentity = { source: "manual", subject: "stale tree name" };
const treeFallbacks = fallbackRestores;
await withStdoutTTY(() => handlers.get("session_tree")({}, ctx));
assert.deepEqual(publishedIdentity, { source: "", subject: "" },
  "unnamed tree navigation clears a stale manual Pi identity");
assert.equal(fallbackRestores, treeFallbacks + 1,
  "unnamed tree navigation restores worktree fallback state");

currentSessionName = "named nested session";
taskStatus = "completed\tmanual\tfinished task";
const nestedBeforeAgentStart = calls.length;
await handlers.get("before_agent_start")({
  prompt: "continue nested work",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
assert.equal(calls.slice(nestedBeforeAgentStart).some((call) =>
  call.command === "tmux-agent-subject" && call.args[0] === "set"), false,
  "non-TTY before_agent_start does not mutate the tmux subject");

const nestedSpecWrites = calls.filter((call) => call.command === "tmux"
  && call.args[0] === "set-option"
  && call.args.includes("@agent_current_spec_path")).length;
await handlers.get("tool_call")({
  toolName: "edit",
  input: { path: `${worktreeRoot}/docs/superpowers/specs/design.md` },
}, ctx);
await handlers.get("tool_result")({
  toolName: "bash",
  input: { command: "cat docs/superpowers/specs/design.md" },
  isError: false,
}, ctx);
assert.equal(calls.filter((call) => call.command === "tmux"
  && call.args[0] === "set-option"
  && call.args.includes("@agent_current_spec_path")).length, nestedSpecWrites,
  "non-TTY edit and bash events do not write the tmux spec path");

currentSessionName = "";
taskStatus = "";
publishedIdentity = { source: "", subject: "" };
goalChildDeferred = undefined;
await withStdoutTTY(async () => {
  await handlers.get("before_agent_start")({
    prompt: "initial automatic naming prompt",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
});
assert.equal(currentSessionName, "generated goal",
  "successful automatic naming sets the Pi session name");
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "generated goal",
}, "successful automatic naming publishes the generated session name");

currentSessionName = "";
const invalidGoalOutput = "private first line\nprivate second line\n";
goalChildResultQueue.push(ok(invalidGoalOutput));
const invalidGoalWarningIndex = warnings.length;
await handlers.get("before_agent_start")({
  prompt: "prompt content must not be logged",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(warnings.length, invalidGoalWarningIndex + 1,
  "invalid goal output emits one diagnostic");
assert.equal(warnings.at(-1)[0], "[managed-hooks] session goal failed");
assert.deepEqual(warnings.at(-1)[1], {
  stage: "evaluation",
  reason: "invalid-output",
  validation: "multiline",
  code: 0,
  killed: false,
  stdout: { type: "string", length: invalidGoalOutput.length, lines: 3 },
  stderr: { type: "string", length: 0, lines: 0 },
}, "invalid goal output reports safe shape and validation details");
assert.equal(JSON.stringify(warnings.at(-1)).includes("private first line"), false,
  "invalid goal diagnostics do not include generated output");
assert.equal(JSON.stringify(warnings.at(-1)).includes("prompt content"), false,
  "invalid goal diagnostics do not include prompt content");

currentSessionName = "";
goalChildResultQueue.push({
  stdout: "private failed output",
  stderr: "provider details",
  code: 7,
  killed: false,
});
await handlers.get("before_agent_start")({
  prompt: "another private prompt",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.deepEqual(warnings.at(-1)[1], {
  stage: "evaluation",
  reason: "exit",
  code: 7,
  killed: false,
  stdout: { type: "string", length: 21, lines: 1 },
  stderr: { type: "string", length: 16, lines: 1 },
}, "failed goal child reports exit and stream shape without stream content");
assert.equal(JSON.stringify(warnings.at(-1)).includes("provider details"), false,
  "failed goal diagnostics do not include stderr content");

currentSessionName = "";
goalChildResultQueue.push({ stdout: "", stderr: "", code: 0, killed: true });
await handlers.get("before_agent_start")({
  prompt: "private timeout prompt",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.deepEqual(warnings.at(-1)[1], {
  stage: "evaluation",
  reason: "timeout",
  code: 0,
  killed: true,
  stdout: { type: "string", length: 0, lines: 0 },
  stderr: { type: "string", length: 0, lines: 0 },
}, "timed-out goal child reports the production exec result shape");

currentSessionName = "";
const privateException = new Error("private exception message");
privateException.name = "private exception name";
goalChildResultQueue.push(privateException);
await handlers.get("before_agent_start")({
  prompt: "private exception prompt",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.deepEqual(warnings.at(-1)[1], {
  stage: "evaluation",
  reason: "exception",
}, "child exception omits mutable exception metadata");
assert.equal(JSON.stringify(warnings.at(-1)).includes("private exception"), false,
  "exception diagnostics do not include exception or prompt content");

currentSessionName = "";
sessionNameError = new Error("private application failure");
goalChildResultQueue.push(ok("valid generated goal\n"));
await handlers.get("before_agent_start")({
  prompt: "private application prompt",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
sessionNameError = undefined;
assert.deepEqual(warnings.at(-1)[1], {
  stage: "name-application",
  reason: "exception",
}, "name application failure is distinct from child evaluation failure");
assert.equal(JSON.stringify(warnings.at(-1)).includes("private application"), false,
  "name application diagnostics omit exception and prompt content");

currentSessionName = "";
taskStatus = "";
goalChildIgnoresAbort = true;
goalChildDeferred = deferred();
const staleInitialGoal = goalChildDeferred;
await handlers.get("before_agent_start")({
  prompt: "initial evaluator prompt",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
currentSessionName = "manual name during generation";
await withStdoutTTY(() => handlers.get("session_info_changed")({
  name: currentSessionName,
}, ctx));
staleInitialGoal.resolve(ok("stale generated goal\n"));
goalChildDeferred = undefined;
goalChildIgnoresAbort = false;
await flushAsyncWork();
assert.equal(currentSessionName, "manual name during generation",
  "manual name wins over stale automatic generation");
assert.equal(sessionNames.includes("stale generated goal"), false,
  "stale automatic generation does not rename the session");
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "manual name during generation",
});

currentSessionName = "";
taskStatus = "";
goalChildIgnoresAbort = true;
goalChildDeferred = deferred();
const staleGoalAfterClear = goalChildDeferred;
const sessionNameCountBeforeClear = sessionNames.length;
await handlers.get("before_agent_start")({
  prompt: "clear name during initial evaluation",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
await withStdoutTTY(() => handlers.get("session_info_changed")({ name: "" }, ctx));
staleGoalAfterClear.resolve(ok("stale goal after clear\n"));
goalChildDeferred = undefined;
goalChildIgnoresAbort = false;
await flushAsyncWork();
assert.equal(currentSessionName, "",
  "clearing the name wins over stale automatic generation");
assert.equal(sessionNames.length, sessionNameCountBeforeClear,
  "stale automatic generation does not restore a cleared name");

currentSessionName = "";
goalChildIgnoresAbort = true;
goalChildDeferred = deferred();
const staleGoalAfterShutdown = goalChildDeferred;
await handlers.get("before_agent_start")({
  prompt: "shutdown during initial evaluation",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
await handlers.get("session_shutdown")({}, ctx);
sessionContextIsStale = true;
staleGoalAfterShutdown.resolve(ok("stale goal after shutdown\n"));
goalChildDeferred = undefined;
goalChildIgnoresAbort = false;
await flushAsyncWork();
sessionContextIsStale = false;
assert.equal(currentSessionName, "",
  "automatic naming does not restore a name after shutdown");
assert.equal(staleContextReads, 0,
  "automatic naming does not read a stale context after shutdown");

branch = "main";
const destructiveCases = [
  "git worktree add ../x",
  "command git -C /repo worktree remove ../x",
  'git -C "/repo with spaces" worktree add ../x',
  "git switch -c new-branch",
  "env X=1 git -C /repo branch -m old new",
  "git commit -m test",
  "git -c advice.detachedHead=false commit -m test",
  'git -c user.name="A B" commit -m test',
  "git -C /repo\\ x commit -m test",
  'git -C $(pwd) commit -m test',
  'git -C $(dirname $(pwd)) commit -m test',
  'git -C `dirname "$PWD"` commit -m test',
  "git --git-dir /repo/.git commit -m test",
  'git --git-dir="/repo with spaces/.git" commit -m test',
  "git --no-pager commit -m test",
  "sudo -E git commit -m test",
  "bash -lc 'git commit -m test'",
  "echo ok; git commit -m test",
  "echo $(git commit -m nested)",
  "echo `git commit -m nested-backtick`",
  "echo \"<<'EOF'\"\necho $(git commit -m after-quoted-marker)",
  "cat <<EOF\n$(git commit -m expanded)\nEOF",
  "cat <<ONE <<'TWO'\n$(git commit -m expanded-first)\nONE\nliteral second body\nTWO",
  "git push origin HEAD:main",
  "git push origin :main",
  "git push origin :",
  "git push --mirror origin",
  "git push origin --all",
  "git push",
  "git push -o ci.skip origin HEAD",
  "sh -c 'git push origin HEAD:main'",
  "cd /repo; git push",
  `true | cd ${worktreeRoot} && git push`,
  `cd ${worktreeRoot} && false || git push`,
  `(cd ${worktreeRoot}); git push`,
  `cd ${worktreeRoot} && git -C "$TARGET" push`,
  `cd ${worktreeRoot} && GIT_DIR=/repo/.git git push`,
  'cd "$PWD" && git push',
  'cd "$(pwd)" && git push',
  "git add -f docs/superpowers/specs/design.md",
  "cd docs && git add -f superpowers/specs/design.md",
];
for (const command of destructiveCases) {
  const result = await handlers.get("tool_call")({
    toolName: "bash",
    input: { command },
  }, ctx);
  assert.equal(result?.block, true, `blocks destructive Git command: ${command}`);
}

failedGitRootCwds.add("/repo");
let result = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git -C /repo push" },
}, { ...ctx, cwd: worktreeRoot });
failedGitRootCwds.clear();
assert.equal(result?.block, true, "fails closed when the selected Git root cannot be resolved");

failedBranchCwds.add("/repo");
result = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git -C /repo push" },
}, { ...ctx, cwd: worktreeRoot });
failedBranchCwds.clear();
assert.equal(result?.block, true, "fails closed when the selected branch cannot be resolved");

const safeMainCases = [
  "git branch --list feature",
  "git grep branch README.md",
  "git grep commit README.md",
  "git grep worktree README.md",
  "bash ~/.local/share/skills/_commit/commit.sh message",
  "git push --tags",
  "git push --dry-run",
  "git push origin feature",
  "git add docs/superpowers/specs/design.md",
  "cat <<'EOF'\ngit branch example\nEOF",
  "cat <<'EOF'\n$(git commit -m literal)\nEOF",
  "cat <<'ONE' <<'TWO'\n$(git commit -m literal-one)\nONE\n$(git commit -m literal-two)\nTWO",
  "cat <<E\"OF\"\n$(git commit -m literal-mixed-quote)\nEOF",
  "cat <<E\"\\Q\"\nEQ\n$(git commit -m literal-backslash)\nE\\Q",
  `git -C ${worktreeRoot} push`,
  `cd ./${path.relative("/repo", worktreeRoot)} && git push`,
];
for (const command of safeMainCases) {
  const allowed = await handlers.get("tool_call")({
    toolName: "bash",
    input: { command },
  }, ctx);
  assert.equal(allowed, undefined, `allows non-destructive Git command: ${command}`);
}

const longInspectionCommand = [
  ...Array.from({ length: 25 }, (_, index) =>
    `git -C /repo rev-parse HEAD > /tmp/revision-${index}.txt`),
  `git ${Array.from({ length: 25 }, () => "-C/repo").join(" ")} rev-parse HEAD`,
  `git ${Array.from({ length: 25 }, () => "--no-pager").join(" ")} rev-parse HEAD`,
  `git ${Array.from({ length: 25 }, () => "--git-dir=/repo/.git").join(" ")} rev-parse HEAD`,
  `git ${Array.from({ length: 25 }, () => '-c user.name="A B"').join(" ")} rev-parse HEAD`,
].join("\n");
const inspectionStartedAt = performance.now();
const longInspectionResult = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: longInspectionCommand },
}, ctx);
const inspectionElapsedMs = performance.now() - inspectionStartedAt;
assert.equal(longInspectionResult, undefined,
  "allows a long multi-line Git inspection command");
assert.ok(inspectionElapsedMs < 1000,
  `parses a long multi-line Git inspection command promptly (${inspectionElapsedMs} ms)`);

result = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "echo $(cd /repo && git push)" },
}, { ...ctx, cwd: worktreeRoot });
assert.equal(result?.block, true,
  "blocks a nested push after its command substitution changes to main");

result = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "echo `cd /repo && git push`" },
}, { ...ctx, cwd: worktreeRoot });
assert.equal(result?.block, true,
  "blocks a nested push after its backtick substitution changes to main");

branch = "feature";
result = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push" },
}, ctx);
assert.equal(result, undefined, "allows implicit push from a verified feature branch");

console.log("pi managed hook race and Git parsing checks complete");
NODE

PI_HOOK_TEST_WORKTREE="$TMPROOT/worktree" \
  "${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/managed-hooks.mjs"
