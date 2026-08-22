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
let closeError;
let readTailError;
let pendingReadTail;
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
    if (pendingReadTail) return pendingReadTail.promise;
    return (logContents.get(logPath) || "").slice(-maxBytes);
  },
  close(fd) {
    closeCalls.push(fd);
    if (closeError) throw closeError;
  },
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
let setActiveToolsError;
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
    if (setActiveToolsError) throw setActiveToolsError;
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

const deferred = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
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
assert.equal(classify("ssh dev.example.com 'bin/provision --tags common_role'"), true);
assert.equal(classify("ssh -o BatchMode=yes dev.example.com './bin/test ci'"), true);
assert.equal(classify("ssh user@192.0.2.1 bin/test"), true);
assert.equal(classify("ssh user@2001:db8::1 bin/test"), true);
assert.equal(classify("ssh localhost bin/test"), true);
assert.equal(classify("ssh user@localhost bin/test"), true);
assert.equal(classify("ssh dev bin/test"), false);
assert.equal(classify("ssh user@dev bin/test"), false);
assert.equal(classify("ssh -F /tmp/ssh-config dev.example.com './bin/test ci'"), false);
assert.equal(classify("ssh -I /tmp/provider.so dev.example.com bin/test"), false);
assert.equal(classify("ssh -J bastion dev.example.com bin/test"), false);
assert.equal(classify("ssh -o ProxyJump=bastion dev.example.com bin/test"), false);
assert.equal(classify("ssh -o PKCS11Provider=/tmp/provider.so dev.example.com bin/test"), false);
assert.equal(classify("ssh -o=PKCS11Provider=/tmp/provider.so dev.example.com bin/test"), false);
assert.equal(classify("ssh -o SecurityKeyProvider=/tmp/provider.so dev.example.com bin/test"), false);
assert.equal(classify("ssh -o=SecurityKeyProvider=/tmp/provider.so dev.example.com bin/test"), false);
assert.equal(classify("ssh -o 'ProxyCommand=touch /tmp/pwn' dev.example.com bin/test"), false);
assert.equal(classify("ssh -o 'LocalCommand=touch /tmp/pwn' dev.example.com bin/test"), false);
assert.equal(classify("ssh -o PermitLocalCommand=yes dev.example.com bin/test"), false);
assert.equal(classify("ssh -o ControlMaster=yes dev.example.com bin/test"), false);
assert.equal(classify("ssh -o ControlPersist=yes dev.example.com bin/test"), false);
assert.equal(classify("ssh -o ControlPath=/tmp/ssh-master dev.example.com bin/test"), false);
assert.equal(classify("ssh -o 'KnownHostsCommand=touch /tmp/pwn' dev.example.com bin/test"), false);
assert.equal(classify("ssh dev.example.com 'cd /repo && ./bin/test ci'"), true);
assert.equal(classify("bin/provision | tee /tmp/log"), false);
assert.equal(classify("bin/test\nprintf unsafe"), false);
assert.equal(classify("env CI=1 bin/test"), false);
assert.equal(classify("bin/test $(date)"), false);
assert.equal(classify("ssh dev.example.com 'bin/test; rm -rf /tmp/x'"), false);
assert.equal(classify('ssh dev.example.com bin/test "$NMB_REMOTE_ARGS"'), false);
assert.equal(classify('ssh -F "$HOME/.ssh/config" dev.example.com bin/test'), false);
assert.equal(classify("ssh dev.example.com 'bin/test $NMB_REMOTE_ARGS'"), false);
assert.equal(classify("ssh dev.example.com 'bin/test *.sh'"), false);
assert.equal(classify("ssh dev.example.com 'bin/test file?.sh'"), false);
assert.equal(classify("ssh dev.example.com 'bin/test files[0-9]'"), false);
assert.equal(classify("ssh dev.example.com 'bin/test {safe,unsafe}'"), false);
assert.equal(classify("ssh dev.example.com 'bin/test ~/suite'"), false);
assert.equal(classify("ssh -f dev.example.com bin/test"), false);
assert.equal(classify("ssh -vf dev.example.com bin/test"), false);
assert.equal(classify("ssh -N dev.example.com bin/test"), false);
assert.equal(classify("ssh -vs dev.example.com bin/test"), false);
assert.equal(classify("ssh -G dev.example.com bin/test"), false);
assert.equal(classify("ssh -V dev.example.com bin/test"), false);
assert.equal(classify("ssh -O check dev.example.com bin/test"), false);
assert.equal(classify("ssh -Q cipher dev.example.com bin/test"), false);
assert.equal(classify("ssh -W host:22 dev.example.com bin/test"), false);
assert.equal(classify("ssh -o ForkAfterAuthentication=yes dev.example.com bin/test"), false);
assert.equal(classify("ssh -o 'ForkAfterAuthentication yes' dev.example.com bin/test"), false);
assert.equal(classify("ssh -oForkAfterAuthentication=yes dev.example.com bin/test"), false);
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
assert.equal(builtInCalls[0].cwd, context.cwd,
  "delegated Bash uses the current session working directory");
const movedContext = { ...context, cwd: "/repo/other-session" };
await registeredBash.execute(
  "delegate-2", { command: "pwd" }, undefined, undefined, movedContext,
);
assert.equal(builtInCalls.at(-1).cwd, "/repo/other-session");

const spawnCountBeforeInvalidTimeouts = spawnCalls.length;
for (const [timeout, message] of [
  [0, "Invalid timeout: must be a finite number of seconds"],
  [-1, "Invalid timeout: must be a finite number of seconds"],
  [Number.POSITIVE_INFINITY, "Invalid timeout: must be a finite number of seconds"],
  [2_147_483.648, "Invalid timeout: maximum is 2147483.647 seconds"],
]) {
  await assert.rejects(
    registeredBash.execute(
      "invalid-timeout", { command: "bin/test", timeout }, undefined, undefined, context,
    ),
    (error) => error.message === message,
  );
}
assert.equal(spawnCalls.length, spawnCountBeforeInvalidTimeouts,
  "invalid managed timeouts do not spawn a process");

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

await assert.rejects(
  registeredBash.execute(
    "call-2", { command: "./bin/test ci" }, undefined, undefined, context,
  ),
  /bg-1 is already active/,
);

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
assert.equal(sentMessages[0].message.content.split("\n").length, 200,
  "the complete injected message is capped at 200 lines");
assert.deepEqual(sentMessages[0].options, { triggerTurn: true, deliverAs: "steer" });
const changesAfterFirstFinish = activeToolChanges.length;
firstChild.emitExit(0);
await flush();
assert.equal(activeToolChanges.length, changesAfterFirstFinish);
assert.equal(sentMessages.length, 1);

ids.push("bg-ssh-config");
const sshConfigChild = new ControlledChild(4214);
spawnQueue.push(sshConfigChild);
await registeredBash.execute(
  "call-ssh-config",
  { command: "ssh -o BatchMode=yes dev.example.com './bin/test ci'" },
  undefined,
  undefined,
  context,
);
assert.equal(
  spawnCalls.at(-1).command,
  "ssh -F /dev/null -o 'BatchMode=yes' -o 'ControlMaster=no' -o 'ControlPath=none' -o 'ControlPersist=no' -o 'ForkAfterAuthentication=no' -o 'ProxyCommand=none' -o 'PermitLocalCommand=no' -o 'KnownHostsCommand=none' '-o' 'BatchMode=yes' 'dev.example.com' './bin/test ci'",
  "managed SSH rejects aliases and disables configuration hooks",
);
sshConfigChild.emitExit(0);
await flush();

ids.push("bg-pending-tail");
const pendingTailChild = new ControlledChild(4210);
spawnQueue.push(pendingTailChild);
await registeredBash.execute(
  "call-pending-tail", { command: "bin/test" }, undefined, undefined, context,
);
pendingReadTail = deferred();
const messagesBeforePendingTail = sentMessages.length;
pendingTailChild.emitExit(0);
await flush();
assert.deepEqual(latestHandler("session_before_switch")({}, context), { cancel: true },
  "session switching stays blocked until completion injection finishes");
await assert.rejects(
  registeredBash.execute(
    "call-during-completion", { command: "bin/test-ruby" }, undefined, undefined, context,
  ),
  /is already active/,
  "a second managed job cannot start while completion is pending",
);
assert.equal(sentMessages.length, messagesBeforePendingTail);
pendingReadTail.resolve("pending tail complete");
pendingReadTail = undefined;
await flush();
assert.equal(sentMessages.length, messagesBeforePendingTail + 1);
assert.equal(sentMessages.at(-1).message.details.id, "bg-pending-tail");
assert.equal(activeTools.includes("bash"), true,
  "the normal tool set is restored after completion injection finishes");
assert.equal(latestHandler("session_before_switch")({}, context), undefined,
  "session switching is allowed after completion injection finishes");

ids.push("bg-timeout");
const timeoutChild = new ControlledChild(4211);
spawnQueue.push(timeoutChild);
await registeredBash.execute(
  "call-timeout", { command: "bin/test", timeout: 30 }, undefined, undefined, context,
);
const timeoutTimer = timers.at(-1);
assert.equal(timeoutTimer.milliseconds, 30_000,
  "managed Bash timeout is scheduled in milliseconds");
const killsBeforeTimeout = killCalls.length;
timeoutTimer.callback();
assert.deepEqual(killCalls.at(-1), { pid: 4211, signal: "SIGTERM" });
assert.equal(killCalls.length, killsBeforeTimeout + 1);
clock = 33_000;
const messagesBeforeTimeoutExit = sentMessages.length;
timeoutChild.emitExit(null, "SIGTERM");
await flush();
assert.equal(sentMessages.length, messagesBeforeTimeoutExit,
  "timeout completion waits for process-group SIGKILL escalation");
const timeoutKillTimer = timers.at(-1);
assert.equal(timeoutKillTimer.milliseconds, 5000);
timeoutKillTimer.callback();
await flush();
assert.deepEqual(killCalls.at(-1), { pid: 4211, signal: "SIGKILL" });
assert.equal(sentMessages.at(-1).message.details.timedOut, true);
assert.equal(sentMessages.at(-1).message.details.timeoutSeconds, 30);
assert.match(sentMessages.at(-1).message.content, /timeout after 30s/);

ids.push("bg-timeout-normal");
const timeoutNormalChild = new ControlledChild(4212);
spawnQueue.push(timeoutNormalChild);
await registeredBash.execute(
  "call-timeout-normal", { command: "bin/test", timeout: 60 }, undefined, undefined, context,
);
const normalTimeoutTimer = timers.at(-1);
const killsBeforeNormalCompletion = killCalls.length;
timeoutNormalChild.emitExit(0);
await flush();
assert.equal(normalTimeoutTimer.cleared, true,
  "normal completion clears the managed Bash timeout");
assert.equal(killCalls.length, killsBeforeNormalCompletion,
  "normal completion does not terminate the process group");
assert.equal(sentMessages.at(-1).message.details.timedOut, false);

ids.push("bg-timeout-max");
const timeoutMaxChild = new ControlledChild(4215);
spawnQueue.push(timeoutMaxChild);
await registeredBash.execute(
  "call-timeout-max",
  { command: "bin/test", timeout: 2_147_483.647 },
  undefined,
  undefined,
  context,
);
const maxTimeoutTimer = timers.at(-1);
assert.equal(maxTimeoutTimer.milliseconds, 2_147_483_647,
  "the built-in Bash maximum timeout remains valid");
timeoutMaxChild.emitExit(0);
await flush();
assert.equal(maxTimeoutTimer.cleared, true);

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
const cancelMessagesBeforeExit = sentMessages.length;
const cancelKillTimer = timers.at(-1);
assert.equal(cancelKillTimer.milliseconds, 5000);
cancelChild.emitExit(null, "SIGTERM");
await flush();
assert.equal(sentMessages.length, cancelMessagesBeforeExit,
  "leader exit does not complete cancellation before group escalation");
cancelKillTimer.callback();
await flush();
assert.deepEqual(killCalls.at(-1), { pid: 4204, signal: "SIGKILL" });
assert.equal(sentMessages.length, cancelMessagesBeforeExit + 1);

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

ids.push("bg-reload-gap");
const reloadGapChild = new ControlledChild(4215);
spawnQueue.push(reloadGapChild);
await registeredBash.execute(
  "call-reload-gap", { command: "bin/test" }, undefined, undefined, context,
);
const messagesBeforeReloadGap = sentMessages.length;
latestHandler("session_shutdown")({ reason: "reload" }, context);
reloadGapChild.emitExit(0);
await flush();
assert.equal(sentMessages.length, messagesBeforeReloadGap,
  "an exit in the reload gap does not use the stale controller");
module.default(pi);
registeredBash = registeredTools.at(-1);
latestHandler("session_start")({}, context);
await flush();
assert.equal(sentMessages.length, messagesBeforeReloadGap + 1,
  "the replacement controller completes an exit from the reload gap");
assert.equal(sentMessages.at(-1).message.details.id, "bg-reload-gap");

ids.push("bg-reload-pending");
const reloadPendingChild = new ControlledChild(4213);
spawnQueue.push(reloadPendingChild);
await registeredBash.execute(
  "call-reload-pending", { command: "bin/test" }, undefined, undefined, context,
);
pendingReadTail = deferred();
const oldMessageCount = sentMessages.length;
reloadPendingChild.emitExit(0);
await flush();
const reloadedMessages = [];
const reloadedToolChanges = [];
let reloadedActiveTools = ["read", "grep", "find", "ls", "bash", "edit", "write", "subagent"];
const reloadedPi = {
  ...pi,
  getActiveTools() { return [...reloadedActiveTools]; },
  setActiveTools(tools) {
    reloadedActiveTools = [...tools];
    reloadedToolChanges.push([...tools]);
  },
  sendMessage(message, options) { reloadedMessages.push({ message, options }); },
};
module.default(reloadedPi);
latestHandler("session_start")({}, context);
assert.deepEqual(reloadedToolChanges.at(-1), ["read", "grep", "find", "ls"]);
pendingReadTail.resolve("reload overlap complete");
pendingReadTail = undefined;
await flush();
assert.equal(sentMessages.length, oldMessageCount,
  "the stale extension does not inject completion after reload");
assert.equal(reloadedMessages.length, 1,
  "the current extension injects completion after reload");
assert.equal(reloadedMessages[0].message.details.id, "bg-reload-pending");
assert.deepEqual(reloadedToolChanges.at(-1), [
  "read", "grep", "find", "ls", "bash", "edit", "write", "subagent",
]);
assert.equal(latestHandler("session_before_switch")({}, context), undefined,
  "reload-overlap completion clears active state");
activeTools = ["read", "grep", "find", "ls", "bash", "edit", "write", "subagent"];
module.default(pi);
latestHandler("session_start")({}, context);
registeredBash = registeredTools.at(-1);

ids.push("bg-quit");
const quitChild = new ControlledChild(4206);
spawnQueue.push(quitChild);
await registeredBash.execute("call-7", { command: "bin/test" }, undefined, undefined, context);
const messagesBeforeQuit = sentMessages.length;
let shutdownResolved = false;
const shutdownPromise = latestHandler("session_shutdown")({ reason: "quit" }, context)
  .then(() => { shutdownResolved = true; });
await flush();
assert.deepEqual(killCalls.at(-1), { pid: 4206, signal: "SIGTERM" });
assert.equal(shutdownResolved, false,
  "shutdown waits while the process ignores SIGTERM");
const shutdownKillTimer = timers.at(-1);
assert.equal(shutdownKillTimer.milliseconds, 5000);
shutdownKillTimer.callback();
assert.deepEqual(killCalls.at(-1), { pid: 4206, signal: "SIGKILL" });
await flush();
assert.equal(shutdownResolved, false,
  "shutdown waits for process exit after SIGKILL");
quitChild.emitExit(null, "SIGKILL");
await shutdownPromise;
await flush();
assert.equal(shutdownResolved, true);
assert.equal(sentMessages.length, messagesBeforeQuit,
  "quit does not inject completion into a shutting-down session");

ids.push("bg-quit-finishing");
const finishingQuitChild = new ControlledChild(4214);
spawnQueue.push(finishingQuitChild);
pendingReadTail = deferred();
await registeredBash.execute(
  "call-quit-finishing", { command: "bin/test" }, undefined, undefined, context,
);
const messagesBeforeFinishingQuit = sentMessages.length;
finishingQuitChild.emitExit(0);
await flush();
let finishingShutdownResolved = false;
const finishingShutdown = latestHandler("session_shutdown")({ reason: "quit" }, context)
  .then(() => { finishingShutdownResolved = true; });
await flush();
assert.equal(finishingShutdownResolved, true,
  "shutdown does not wait on termination after child completion starts");
assert.equal(sentMessages.length, messagesBeforeFinishingQuit,
  "quit suppresses completion that was already reading the log");
pendingReadTail.resolve("late completion");
pendingReadTail = undefined;
await finishingShutdown;
await flush();
assert.equal(sentMessages.length, messagesBeforeFinishingQuit,
  "late log completion stays suppressed after quit");

makeLogError = new Error("disk full");
ids.push("bg-log-error");
await assert.rejects(
  registeredBash.execute(
    "call-8", { command: "bin/test" }, undefined, undefined, context,
  ),
  /disk full/,
);
makeLogError = undefined;

spawnError = new Error("spawn denied");
closeError = new Error("close denied");
ids.push("bg-spawn-error");
await assert.rejects(
  registeredBash.execute(
    "call-9", { command: "bin/test" }, undefined, undefined, context,
  ),
  /spawn denied/,
);
assert.match(warnings.at(-1), /close denied/,
  "descriptor close failures after spawn errors are logged");
spawnError = undefined;
closeError = undefined;

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

activeTools = ["read", "grep", "find", "ls", "bash", "edit", "write", "subagent"];
ids.push("bg-restore-error");
const restoreErrorChild = new ControlledChild(4209);
spawnQueue.push(restoreErrorChild);
await registeredBash.execute("call-12", { command: "bin/test" }, undefined, undefined, context);
const messagesBeforeRestoreError = sentMessages.length;
setActiveToolsError = new Error("tool restore denied");
restoreErrorChild.emitExit(0);
await flush();
assert.match(warnings.at(-1), /could not restore tools for bg-restore-error: tool restore denied/);
assert.equal(sentMessages.length, messagesBeforeRestoreError + 1,
  "tool restoration failure does not prevent completion injection");
assert.equal(sentMessages.at(-1).message.details.id, "bg-restore-error");
assert.equal(sentMessages.at(-1).message.details.code, 0);
assert.deepEqual(sentMessages.at(-1).options, { triggerTurn: true, deliverAs: "steer" });
assert.equal(globalThis[STATE].active.id, "bg-restore-error",
  "a failed tool restoration keeps recovery state");
assert.equal(activeTools.includes("bash"), false,
  "a failed tool restoration keeps the fake tool list gated");

setActiveToolsError = undefined;
await commands.get("background-jobs").handler("", context);
assert.match(notices.at(-1).message, /bg-restore-error completed/);
assert.equal(globalThis[STATE].active, undefined,
  "the status command releases recovered job state");
assert.equal(activeTools.includes("bash"), true,
  "the status command retries tool restoration");
assert.equal(closeCalls.length, spawnCalls.length + 1,
  "every successful log creation closes its parent descriptor");

console.log("Pi managed background job checks complete");
NODE

"${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/managed-background-jobs.mjs"
