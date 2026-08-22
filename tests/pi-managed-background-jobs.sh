#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
EXTENSION="$REPO_ROOT/roles/common/files/pi/extensions/managed-background-jobs.ts"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
cp "$EXTENSION" "$TMPROOT/managed-background-jobs.mjs"
mkdir -p "$TMPROOT/node_modules/@earendil-works/pi-coding-agent"
cat >"$TMPROOT/node_modules/@earendil-works/pi-coding-agent/package.json" <<'JSON'
{"name":"@earendil-works/pi-coding-agent","type":"module","exports":"./index.js"}
JSON
cat >"$TMPROOT/node_modules/@earendil-works/pi-coding-agent/index.js" <<'JS'
export function createBashToolDefinition(cwd) {
  return globalThis[Symbol.for("nmb.pi-managed-background-jobs.test-built-in")](cwd);
}
JS

node_cmd=(node)
if ! command -v node >/dev/null 2>&1; then
  node_version="$(yq -r '.tool_versions.runtimes.node' "$REPO_ROOT/vars/tool_versions.yml")"
  node_cmd=("${MISE_BIN:-$HOME/.local/bin/mise}" exec "node@$node_version" -- node)
fi

cat >"$TMPROOT/check.mjs" <<'NODE'
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const ADAPTERS = Symbol.for("nmb.pi-managed-background-jobs.adapters");
const STATE = Symbol.for("nmb.pi-managed-background-jobs.process-state");
const BUILT_IN = Symbol.for("nmb.pi-managed-background-jobs.test-built-in");
delete globalThis[STATE];

const builtInCalls = [];
globalThis[BUILT_IN] = (cwd) => ({
  name: "bash",
  label: "bash",
  description: "fake bash",
  promptSnippet: "fake",
  promptGuidelines: ["fake"],
  parameters: { type: "object" },
  renderCall() {},
  renderResult() {},
  async execute(toolCallId, params, signal, onUpdate, ctx) {
    builtInCalls.push({ cwd, toolCallId, params, signal, onUpdate, ctx });
    return { content: [{ type: "text", text: `delegated: ${params.command}` }] };
  },
});

class ControlledChild extends EventEmitter {
  constructor(pid) {
    super();
    this.pid = pid;
    this.completed = false;
  }
  emitExit(code, signal = null) {
    this.completed = true;
    this.emit("exit", code, signal);
  }
}

let clock = 1000;
let nextPid = 4100;
const spawnQueue = [];
const spawnCalls = [];
const logContents = new Map();
const closeCalls = [];
const killCalls = [];
const timers = [];
const warnings = [];
const ids = [];
let makeLogError;
let spawnError;
let readTailError;
const adapters = {
  spawnQueue,
  now: () => clock,
  randomId: () => ids.shift() || "bg-fallback",
  makeLog(sessionId, jobId) {
    if (makeLogError) throw makeLogError;
    const logPath = `/tmp/pi-background-jobs/${sessionId}/${jobId}.log`;
    return { path: logPath, fd: 90 + closeCalls.length };
  },
  spawn(command, options) {
    if (spawnError) throw spawnError;
    const child = spawnQueue.shift() || new ControlledChild(nextPid++);
    spawnCalls.push({ command, options, child });
    return child;
  },
  async readTail(logPath, maxBytes) {
    if (readTailError) throw readTailError;
    return (logContents.get(logPath) || "").slice(-maxBytes);
  },
  close(fd) { closeCalls.push(fd); },
  killProcessGroup(pid, signal) { killCalls.push({ pid, signal }); },
  setTimeout(callback, milliseconds) {
    const timer = { callback, milliseconds, cleared: false };
    timers.push(timer);
    return timer;
  },
  clearTimeout(timer) { timer.cleared = true; },
  warn(message) { warnings.push(message); },
};
globalThis[ADAPTERS] = adapters;

const handlerLists = new Map();
const commands = new Map();
const registeredTools = [];
const activeToolChanges = [];
const sentMessages = [];
let activeTools = ["read", "grep", "find", "ls", "bash", "edit", "write", "subagent"];
const pi = {
  activeToolChanges,
  on(event, handler) {
    if (!handlerLists.has(event)) handlerLists.set(event, []);
    handlerLists.get(event).push(handler);
  },
  registerTool(tool) { registeredTools.push(tool); },
  registerCommand(name, definition) { commands.set(name, definition); },
  getActiveTools() { return [...activeTools]; },
  setActiveTools(tools) {
    activeTools = [...tools];
    activeToolChanges.push([...tools]);
  },
  sendMessage(message, options) { sentMessages.push({ message, options }); },
};
const notices = [];
const context = {
  cwd: "/repo/worktree",
  model: { provider: "openai", id: "gpt-test" },
  thinkingLevel: "high",
  sessionManager: {
    getSessionId: () => "session-1",
    getSessionFile: () => "/sessions/session-1.jsonl",
  },
  ui: { notify(message, level) { notices.push({ message, level }); } },
};

const flush = async () => {
  for (let index = 0; index < 8; index += 1) {
    await new Promise((resolve) => setImmediate(resolve));
  }
};
const latestHandler = (event) => handlerLists.get(event).at(-1);

const module = await import(pathToFileURL(extensionPath));
const classify = (command) => Boolean(module.classifyManagedCommand(command));
assert.equal(classify("bin/provision --limit dev"), true);
assert.equal(classify("./bin/test ci"), true);
assert.equal(classify("bin/test-ruby"), true);
assert.equal(classify("ssh dev 'bin/provision --tags common_role'"), true);
assert.equal(classify("ssh -o BatchMode=yes dev './bin/test ci'"), true);
assert.equal(classify("ssh dev 'cd /repo && ./bin/test ci'"), true);
assert.equal(classify("bin/provision | tee /tmp/log"), false);
assert.equal(classify("bin/test\nprintf unsafe"), false);
assert.equal(classify("env CI=1 bin/test"), false);
assert.equal(classify("bin/test $(date)"), false);
assert.equal(classify("ssh dev 'bin/test; rm -rf /tmp/x'"), false);
assert.equal(classify("ssh -p dev bin/test"), false);
assert.equal(classify("ssh dev"), false);
assert.equal(classify("bin/test 'unterminated"), false);

module.default(pi);
let registeredBash = registeredTools.at(-1);
assert.equal(registeredBash.executionMode, "sequential");
assert.equal(registeredBash.promptSnippet, "fake");

const delegateResult = await registeredBash.execute(
  "delegate-1", { command: "printf safe" }, undefined, undefined, context,
);
assert.equal(delegateResult.content[0].text, "delegated: printf safe");
assert.equal(builtInCalls.length, 1);
assert.equal(builtInCalls[0].cwd, process.cwd());

ids.push("bg-1");
const firstChild = new ControlledChild(4201);
spawnQueue.push(firstChild);
const startResult = await registeredBash.execute(
  "call-1", { command: "bin/provision --limit dev" }, undefined, undefined, context,
);
assert.match(startResult.content[0].text, /Managed background job bg-1 started/);
assert.deepEqual(activeToolChanges.at(-1), ["read", "grep", "find", "ls"]);
assert.equal(firstChild.completed, false);
assert.equal(spawnCalls.at(-1).command, "bin/provision --limit dev");
assert.equal(spawnCalls.at(-1).options.cwd, "/repo/worktree");
assert.equal(spawnCalls.at(-1).options.env.PI_SESSION_ID, "session-1");
assert.equal(spawnCalls.at(-1).options.env.PI_SESSION_FILE, "/sessions/session-1.jsonl");
assert.equal(spawnCalls.at(-1).options.env.PI_PROVIDER, "openai");
assert.equal(spawnCalls.at(-1).options.env.PI_MODEL, "gpt-test");
assert.equal(spawnCalls.at(-1).options.env.PI_REASONING_LEVEL, "high");

const secondResult = await registeredBash.execute(
  "call-2", { command: "./bin/test ci" }, undefined, undefined, context,
);
assert.equal(secondResult.isError, true);
assert.match(secondResult.content[0].text, /bg-1 is already active/);

for (const toolName of ["write", "edit", "bash", "subagent", "custom-tool"]) {
  const blocked = latestHandler("tool_call")({ toolName, input: {} }, context);
  assert.deepEqual(blocked, {
    block: true,
    reason: "A managed background job is active. Only read-only inspection tools are available.",
    terminate: false,
  });
}
for (const toolName of ["read", "grep", "find", "ls"]) {
  assert.equal(latestHandler("tool_call")({ toolName, input: {} }, context), undefined);
}
assert.deepEqual(latestHandler("session_before_switch")({}, context), { cancel: true });
assert.deepEqual(latestHandler("session_before_fork")({}, context), { cancel: true });

const longTail = Array.from({ length: 240 }, (_, index) => `line ${index}`).join("\n");
logContents.set("/tmp/pi-background-jobs/session-1/bg-1.log", longTail);
clock = 2500;
firstChild.emitExit(0);
await flush();
assert.deepEqual(activeToolChanges.at(-1), [
  "read", "grep", "find", "ls", "bash", "edit", "write", "subagent",
]);
assert.equal(sentMessages.length, 1);
assert.equal(sentMessages[0].message.customType, "managed-background-job-complete");
assert.equal(sentMessages[0].message.display, true);
assert.equal(sentMessages[0].message.details.code, 0);
assert.equal(sentMessages[0].message.details.durationMs, 1500);
assert.equal(sentMessages[0].message.details.logPath, "/tmp/pi-background-jobs/session-1/bg-1.log");
assert.equal(sentMessages[0].message.details.tail.split("\n").length, 200);
assert.deepEqual(sentMessages[0].options, { triggerTurn: true, deliverAs: "steer" });
const changesAfterFirstFinish = activeToolChanges.length;
firstChild.emitExit(0);
await flush();
assert.equal(activeToolChanges.length, changesAfterFirstFinish);
assert.equal(sentMessages.length, 1);

ids.push("bg-failure");
const failureChild = new ControlledChild(4202);
spawnQueue.push(failureChild);
await registeredBash.execute("call-3", { command: "bin/test" }, undefined, undefined, context);
clock = 3000;
failureChild.emitExit(7);
await flush();
assert.equal(sentMessages.at(-1).message.details.code, 7);
assert.match(sentMessages.at(-1).message.content, /exit 7/);

ids.push("bg-signal");
const signalChild = new ControlledChild(4203);
spawnQueue.push(signalChild);
await registeredBash.execute("call-4", { command: "bin/test-ruby" }, undefined, undefined, context);
signalChild.emitExit(null, "SIGTERM");
await flush();
assert.equal(sentMessages.at(-1).message.details.signal, "SIGTERM");
assert.match(sentMessages.at(-1).message.content, /signal SIGTERM/);

ids.push("bg-cancel");
const cancelChild = new ControlledChild(4204);
spawnQueue.push(cancelChild);
await registeredBash.execute("call-5", { command: "./bin/test" }, undefined, undefined, context);
await commands.get("background-cancel").handler("", context);
assert.deepEqual(killCalls.at(-1), { pid: 4204, signal: "SIGTERM" });
assert.equal(timers.at(-1).milliseconds, 5000);
timers.at(-1).callback();
assert.deepEqual(killCalls.at(-1), { pid: 4204, signal: "SIGKILL" });
cancelChild.emitExit(null, "SIGTERM");
await flush();
assert.equal(timers.at(-1).cleared, true);

ids.push("bg-reload");
const reloadChild = new ControlledChild(4205);
spawnQueue.push(reloadChild);
await registeredBash.execute("call-6", { command: "bin/provision" }, undefined, undefined, context);
const killsBeforeReload = killCalls.length;
latestHandler("session_shutdown")({ reason: "reload" }, context);
assert.equal(killCalls.length, killsBeforeReload);
module.default(pi);
registeredBash = registeredTools.at(-1);
activeToolChanges.length = 0;
latestHandler("session_start")({}, context);
assert.deepEqual(activeToolChanges.at(-1), ["read", "grep", "find", "ls"]);
reloadChild.emitExit(0);
await flush();
assert.deepEqual(activeToolChanges.at(-1), [
  "read", "grep", "find", "ls", "bash", "edit", "write", "subagent",
]);

ids.push("bg-quit");
const quitChild = new ControlledChild(4206);
spawnQueue.push(quitChild);
await registeredBash.execute("call-7", { command: "bin/test" }, undefined, undefined, context);
latestHandler("session_shutdown")({ reason: "quit" }, context);
assert.deepEqual(killCalls.at(-1), { pid: 4206, signal: "SIGTERM" });
quitChild.emitExit(null, "SIGTERM");
await flush();

makeLogError = new Error("disk full");
ids.push("bg-log-error");
const logFailure = await registeredBash.execute(
  "call-8", { command: "bin/test" }, undefined, undefined, context,
);
assert.equal(logFailure.isError, true);
assert.match(logFailure.content[0].text, /disk full/);
makeLogError = undefined;

spawnError = new Error("spawn denied");
ids.push("bg-spawn-error");
const spawnFailure = await registeredBash.execute(
  "call-9", { command: "bin/test" }, undefined, undefined, context,
);
assert.equal(spawnFailure.isError, true);
assert.match(spawnFailure.content[0].text, /spawn denied/);
spawnError = undefined;

ids.push("bg-tail-error");
const tailErrorChild = new ControlledChild(4207);
spawnQueue.push(tailErrorChild);
await registeredBash.execute("call-10", { command: "bin/test" }, undefined, undefined, context);
readTailError = new Error("read denied");
tailErrorChild.emitExit(0);
await flush();
assert.match(warnings.at(-1), /read denied/);
assert.equal(sentMessages.at(-1).message.details.tail, "");
readTailError = undefined;

ids.push("bg-child-error");
const childError = new ControlledChild(4208);
spawnQueue.push(childError);
await registeredBash.execute("call-11", { command: "bin/test" }, undefined, undefined, context);
childError.emit("error", new Error("child failed"));
await flush();
assert.match(warnings.at(-1), /child failed/);
assert.equal(sentMessages.at(-1).message.details.code, null);
assert.equal(sentMessages.at(-1).message.details.signal, null);

await commands.get("background-jobs").handler("", context);
assert.match(notices.at(-1).message, /bg-child-error completed/);
assert.equal(activeTools.includes("bash"), true);
assert.equal(closeCalls.length, spawnCalls.length + 1,
  "every successful log creation closes its parent descriptor");

console.log("Pi managed background job checks complete");
NODE

"${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/managed-background-jobs.mjs"
