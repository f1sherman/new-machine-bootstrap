#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
EXTENSION="$REPO_ROOT/roles/common/files/pi/extensions/managed-hooks.ts"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

cp "$EXTENSION" "$TMPROOT/managed-hooks.mjs"

node_cmd=(node)
if ! command -v node >/dev/null 2>&1; then
  mise_bin="${MISE_BIN:-$HOME/.local/bin/mise}"
  node_version="$(yq -r '.tool_versions.runtimes.node' "$REPO_ROOT/vars/tool_versions.yml")"
  node_cmd=("$mise_bin" exec "node@$node_version" -- node)
fi

cat >"$TMPROOT/check.mjs" <<'NODE'
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const worktreeRoot = process.env.PI_HOOK_TEST_WORKTREE;
const originalHome = process.env.HOME;
const originalManagedChildModelOverride = process.env.PI_MANAGED_CHILD_MODEL;
const originalCodingAgentDir = process.env.PI_CODING_AGENT_DIR;
process.env.HOME = worktreeRoot;
delete process.env.PI_MANAGED_CHILD_MODEL;
fs.mkdirSync(path.join(worktreeRoot, "tests"), { recursive: true });

const managedChildAuthDir = path.join(worktreeRoot, ".pi", "agent");
const managedChildAuthPath = path.join(managedChildAuthDir, "auth.json");
const managedChildOverrideAuthDir = path.join(worktreeRoot, ".pi-override", "agent");
const managedChildOverrideAuthPath = path.join(managedChildOverrideAuthDir, "auth.json");
const managedChildTildeAuthDir = path.join(worktreeRoot, ".pi-tilde", "agent");
const managedChildTildeAuthPath = path.join(managedChildTildeAuthDir, "auth.json");
const managedChildExactTildeAuthPath = path.join(worktreeRoot, "auth.json");
const completeCodexOAuth = {
  "openai-codex": {
    type: "oauth",
    access: "test-access",
    refresh: "test-refresh",
    expires: 0,
  },
};
let authReadCount = 0;
let overrideAuthReadCount = 0;
let tildeAuthReadCount = 0;
let exactTildeAuthReadCount = 0;
let failManagedChildAuthRead = false;
let useMatchingAuthMetadata = false;
const originalReadFileSync = fs.readFileSync;
const originalStatSync = fs.statSync;

function writeManagedChildAuth(contents) {
  fs.mkdirSync(managedChildAuthDir, { recursive: true });
  fs.writeFileSync(managedChildAuthPath, typeof contents === "string" ? contents : JSON.stringify(contents));
}

function replaceManagedChildAuth(contents) {
  const replacementPath = `${managedChildAuthPath}.replacement`;
  fs.writeFileSync(replacementPath, typeof contents === "string" ? contents : JSON.stringify(contents));
  fs.renameSync(replacementPath, managedChildAuthPath);
}

function removeManagedChildAuth() {
  fs.rmSync(managedChildAuthPath, { force: true });
}

function chmodManagedChildAuth(mode) {
  fs.chmodSync(managedChildAuthPath, mode);
}

fs.readFileSync = function managedChildAuthRead(filePath, ...args) {
  const resolvedPath = path.resolve(String(filePath));
  if (resolvedPath === managedChildAuthPath) {
    authReadCount += 1;
    if (failManagedChildAuthRead) throw new Error("managed child auth read failure");
  }
  if (resolvedPath === managedChildOverrideAuthPath) {
    overrideAuthReadCount += 1;
  }
  if (resolvedPath === managedChildTildeAuthPath) {
    tildeAuthReadCount += 1;
  }
  if (resolvedPath === managedChildExactTildeAuthPath) {
    exactTildeAuthReadCount += 1;
  }
  return originalReadFileSync.call(this, filePath, ...args);
};

fs.statSync = function managedChildAuthStat(filePath, ...args) {
  const resolvedPath = path.resolve(String(filePath));
  if (useMatchingAuthMetadata && [managedChildOverrideAuthPath, managedChildTildeAuthPath].includes(resolvedPath)) {
    return { dev: 1, ino: 1, size: 1, mtimeMs: 1, ctimeMs: 1 };
  }
  return originalStatSync.call(this, filePath, ...args);
};

function restoreManagedChildTestState() {
  fs.readFileSync = originalReadFileSync;
  fs.statSync = originalStatSync;
  if (originalHome === undefined) delete process.env.HOME;
  else process.env.HOME = originalHome;
  if (originalManagedChildModelOverride === undefined) delete process.env.PI_MANAGED_CHILD_MODEL;
  else process.env.PI_MANAGED_CHILD_MODEL = originalManagedChildModelOverride;
  if (originalCodingAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
  else process.env.PI_CODING_AGENT_DIR = originalCodingAgentDir;
}

process.once("exit", restoreManagedChildTestState);
writeManagedChildAuth(completeCodexOAuth);
chmodManagedChildAuth(0o600);
const { default: install } = await import(pathToFileURL(extensionPath));

const handlers = new Map();
const calls = [];
const sessionNames = [];
const statuses = [];
const notifications = [];
const customEntries = [];
const appendEntryErrors = [];
let branch = "main";
let branchEntries = [];
let currentSessionName = "";
let windowLabel = "pi main-repo";
let agentWorktreePath = "/repo/main-repo";
let boundPiSessionFile = "/sessions/previous.jsonl";
let activeSessionFile = "/sessions/current.jsonl";
let managedPiSessionName = "";
let taskStatus = "";
let taskStatusFails = false;
let taskStatusDeferred;
const goalChildCalls = [];
let goalChildResults = [];
let goalChildErrors = [];
let goalChildDeferred;
let goalChildIgnoresAbort = false;
let activeGoalChildren = 0;
let maxActiveGoalChildren = 0;

const ok = (stdout = "") => ({ stdout, stderr: "", code: 0, killed: false });
const fail = () => ({ stdout: "", stderr: "", code: 1, killed: false });

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

function abortableGoalResult(promise, signal) {
  if (signal?.aborted) return Promise.resolve({ stdout: "", stderr: "", code: 1, killed: true });
  return new Promise((resolve) => {
    const abort = () => resolve({ stdout: "", stderr: "", code: 1, killed: true });
    signal?.addEventListener("abort", abort, { once: true });
    promise.then((result) => {
      signal?.removeEventListener("abort", abort);
      resolve(result);
    });
  });
}

async function flushAsyncWork() {
  for (let index = 0; index < 8; index += 1) await new Promise((resolve) => setImmediate(resolve));
}

async function withStdoutTTY(isTTY, callback) {
  const originalDescriptor = Object.getOwnPropertyDescriptor(process.stdout, "isTTY");
  Object.defineProperty(process.stdout, "isTTY", { configurable: true, value: isTTY });
  try {
    return await callback();
  } finally {
    if (originalDescriptor) {
      Object.defineProperty(process.stdout, "isTTY", originalDescriptor);
    } else {
      delete process.stdout.isTTY;
    }
  }
}

function isGoalChildArgs(args) {
  const systemPromptIndex = args.indexOf("--system-prompt");
  const systemPrompt = systemPromptIndex === -1 ? "" : args[systemPromptIndex + 1];
  return systemPrompt.includes("session's broad goal");
}

function modelArg(call) {
  const modelIndex = call.args.indexOf("--model");
  return modelIndex === -1 ? "" : call.args[modelIndex + 1];
}

let subjectChildResult = ok("improve tmux labels\n");
let subjectChildError;
let subjectChildExecOptions;
let subjectApplyResult = ok();

const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
  setSessionName(name) {
    currentSessionName = name;
    sessionNames.push(name);
  },
  appendEntry(customType, data) {
    if (appendEntryErrors.length > 0) throw appendEntryErrors.shift();
    customEntries.push({ customType, data });
  },
  async exec(command, args, options = {}) {
    calls.push({ command, args });
    if (command === "tmux-agent-state" && args[0] === "status") {
      if (taskStatusDeferred) return taskStatusDeferred.promise;
      return taskStatusFails ? fail() : ok(taskStatus);
    }
    if (command === "tmux-agent-state") return ok();
    if (command === "tmux-update-pane-label") return ok();
    if (command === "tmux-window-label") return ok();
    if (command === "tmux" && args[0] === "show-options" && args.at(-1) === "@window-label") return ok(`${windowLabel}\n`);
    if (command === "tmux" && args[0] === "show-options" && args.at(-1) === "@agent_worktree_path") return agentWorktreePath ? ok(`${agentWorktreePath}\n`) : fail();
    if (command === "tmux" && args[0] === "show-options" && args.at(-1) === "@persist_pi_session_file") return boundPiSessionFile ? ok(`${boundPiSessionFile}\n`) : fail();
    if (command === "tmux" && args[0] === "show-options" && args.at(-1) === "@pi_managed_session_name") return managedPiSessionName ? ok(`${managedPiSessionName}\n`) : fail();
    if (command === "tmux" && args[0] === "set-option") {
      if (args.includes("@persist_pi_session_file")) boundPiSessionFile = args.at(-1);
      if (args.includes("@pi_managed_session_name")) managedPiSessionName = args.at(-1);
      return ok();
    }
    if (command === "tmux") return fail();
    if (command === "pi") {
      if (isGoalChildArgs(args)) {
        goalChildCalls.push({ args, options });
        activeGoalChildren += 1;
        maxActiveGoalChildren = Math.max(maxActiveGoalChildren, activeGoalChildren);
        const deferredResult = goalChildDeferred;
        try {
          if (goalChildErrors.length > 0) throw goalChildErrors.shift();
          if (deferredResult) {
            const result = goalChildIgnoresAbort
              ? deferredResult.promise
              : abortableGoalResult(deferredResult.promise, options.signal);
            return await result;
          }
          return goalChildResults.shift() ?? ok("KEEP\n");
        } finally {
          activeGoalChildren -= 1;
        }
      }
      subjectChildExecOptions = options;
      if (subjectChildError) throw subjectChildError;
      return subjectChildResult;
    }
    if (command === "tmux-agent-subject") return subjectApplyResult;
    if (command === "git" && args.includes("rev-parse")) {
      if (args.some((arg) => String(arg).startsWith("/missing"))) return fail();
      return ok(args.some((arg) => String(arg).startsWith(worktreeRoot)) ? `${worktreeRoot}\n` : "/repo\n");
    }
    if (command === "git" && args.includes("branch")) {
      return ok(args.includes(worktreeRoot) ? "feature\n" : `${branch}\n`);
    }
    return fail();
  },
};

const subjectSignal = new AbortController().signal;
const ctx = {
  cwd: "/repo/main-repo/src",
  signal: subjectSignal,
  ui: {
    setStatus(key, value) {
      statuses.push({ key, value });
    },
    notify(message, level) {
      notifications.push({ message, level });
    },
  },
  sessionManager: {
    getSessionName() {
      return currentSessionName;
    },
    getSessionFile() {
      return activeSessionFile;
    },
    getBranch() {
      return branchEntries;
    },
  },
};

install(pi);
assert.equal(typeof handlers.get("session_start"), "function", "registers session_start hook");
assert.equal(typeof handlers.get("session_shutdown"), "function", "registers session_shutdown hook");
assert.equal(typeof handlers.get("session_tree"), "function", "registers session_tree hook");
assert.equal(typeof handlers.get("before_agent_start"), "function", "registers before_agent_start hook");
assert.equal(typeof handlers.get("tool_call"), "function", "registers tool_call hook");
assert.equal(typeof handlers.get("tool_result"), "function", "registers tool_result hook");

process.env.TMUX = "1";
process.env.TMUX_PANE = "%1";
delete process.env.TMUX_AGENT_STATE_DIR;

statuses.length = 0;
branchEntries = [];
await handlers.get("session_start")({ reason: "startup" }, ctx);
assert.deepEqual(statuses.at(-1), {
  key: "session-goal",
  value: "goal: determining…",
}, "new sessions show the determining goal placeholder");

statuses.length = 0;
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "old goal" } },
  { type: "custom", customType: "other-extension", data: { subject: "ignore me" } },
  { type: "custom", customType: "session-goal", data: { subject: "  persistent   Pi session goals  " } },
  { type: "custom", customType: "session-goal", data: { subject: "first\nsecond" } },
  { type: "custom", customType: "session-goal", data: { subject: "control\u0007subject" } },
  { type: "custom", customType: "session-goal", data: { subject: "goal: prefixed" } },
  { type: "custom", customType: "session-goal", data: { subject: "KEEP" } },
  { type: "custom", customType: "session-goal", data: { subject: "\"quoted subject\"" } },
  { type: "custom", customType: "session-goal", data: { subject: "x".repeat(81) } },
];
await handlers.get("session_start")({ reason: "resume" }, ctx);
assert.deepEqual(statuses.at(-1), {
  key: "session-goal",
  value: "goal: persistent Pi session goals",
}, "resume skips malformed newest entries and restores the latest valid normalized goal");

const outsideTmuxEntries = customEntries.length;
delete process.env.TMUX;
delete process.env.TMUX_PANE;
branchEntries = [];
currentSessionName = "";
managedPiSessionName = "";
statuses.length = 0;
calls.length = 0;
await handlers.get("session_start")({ reason: "outside tmux" }, ctx);
assert.equal(statuses.at(-1).value, "goal: determining…", "outside tmux renders goal status");
goalChildResults.push(ok("outside tmux goal\n"));
await handlers.get("before_agent_start")({
  prompt: "set a goal outside tmux",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.deepEqual(customEntries.at(-1), {
  customType: "session-goal",
  data: { subject: "outside tmux goal" },
}, "outside tmux persists changed goals");
assert.equal(customEntries.length, outsideTmuxEntries + 1, "outside tmux appends one goal entry");
assert.equal(statuses.at(-1).value, "goal: outside tmux goal", "outside tmux updates goal status");
assert.equal(currentSessionName, "outside tmux goal", "outside tmux names the session from its goal");
assert.equal(calls.some((call) => call.command === "tmux-agent-state" && call.args[0] === "status"), false, "outside tmux goal naming does not query tmux task state");

process.env.TMUX = "1";
process.env.TMUX_PANE = "%1";
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "persistent Pi session goals" } },
];
sessionNames.length = 0;
currentSessionName = "feature-work";
windowLabel = "pi main-repo feature-work";
await handlers.get("session_start")({}, ctx);
windowLabel = "pi main-repo other-work";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.equal(currentSessionName, "feature-work", "manual compact Pi session names are not adopted as managed names");
assert.deepEqual(sessionNames, [], "manual compact-name preservation does not call setSessionName");

currentSessionName = "";
windowLabel = "pi main-repo";
branchEntries = [];
calls.length = 0;
await handlers.get("session_start")({}, ctx);
assert.deepEqual(calls.slice(-7), [
  { command: "tmux-update-pane-label", args: ["%1"] },
  { command: "tmux-window-label", args: ["%1"] },
  { command: "tmux-agent-state", args: ["set-kind", "pi"] },
  { command: "tmux-agent-state", args: ["status"] },
  { command: "tmux-agent-state", args: ["status"] },
  { command: "tmux", args: ["show-options", "-qv", "-p", "-t", "%1", "@window-label"] },
  { command: "tmux", args: ["show-options", "-qv", "-p", "-t", "%1", "@agent_worktree_path"] },
], "session_start verifies canonical task status before using the rendered tmux label");
assert.deepEqual(sessionNames, [], "directory-only pi labels do not set redundant Pi session names");
assert.equal(typeof handlers.get("session_info_changed"), "function", "registers session_info_changed hook");

boundPiSessionFile = "/sessions/previous.jsonl";
activeSessionFile = "/sessions/current.jsonl";
currentSessionName = "Investigate mount probe flapping";
branchEntries = [];
calls.length = 0;
await withStdoutTTY(false, async () => {
  await handlers.get("session_start")({ reason: "non-interactive tmux subject sync" }, ctx);
});
assert.equal(calls.some((call) => call.command === "tmux-agent-subject"), false, "non-TTY changed session_start does not update the interactive pane subject");

boundPiSessionFile = "/sessions/previous.jsonl";
calls.length = 0;
await withStdoutTTY(true, async () => {
  await handlers.get("session_start")({ reason: "interactive tmux subject sync" }, ctx);
});
assert.deepEqual(calls.slice(0, 6), [
  { command: "tmux", args: ["show-options", "-qv", "-p", "-t", "%1", "@persist_pi_session_file"] },
  { command: "tmux-agent-subject", args: ["set", "Investigate mount probe flapping"] },
  { command: "tmux-update-pane-label", args: ["%1"] },
  { command: "tmux-window-label", args: ["%1"] },
  { command: "tmux-agent-state", args: ["set-kind", "pi"] },
  { command: "tmux", args: ["set-option", "-p", "-t", "%1", "@persist_pi_session_file", "/sessions/current.jsonl"] },
], "interactive changed session syncs the subject before labels and rebinds the pane session file");
assert.equal(boundPiSessionFile, "/sessions/current.jsonl", "interactive changed session stores the active session binding");

for (const [name, nextBoundPiSessionFile, nextCurrentSessionName] of [
  ["same binding", "/sessions/current.jsonl", "Investigate mount probe flapping"],
  ["absent previous binding", "", "Investigate mount probe flapping"],
  ["empty current name", "/sessions/previous.jsonl", "   "],
]) {
  boundPiSessionFile = nextBoundPiSessionFile;
  activeSessionFile = "/sessions/current.jsonl";
  currentSessionName = nextCurrentSessionName;
  branchEntries = [];
  calls.length = 0;
  await withStdoutTTY(true, async () => {
    await handlers.get("session_start")({ reason: name }, ctx);
  });
  assert.equal(calls.some((call) => call.command === "tmux-agent-subject"), false, `${name} does not invoke tmux-agent-subject`);
}

boundPiSessionFile = "/sessions/previous.jsonl";
activeSessionFile = "/sessions/current.jsonl";
currentSessionName = "";

assert.equal(typeof handlers.get("tool_result"), "function", "registers tool_result hook");

calls.length = 0;
await withStdoutTTY(false, async () => {
  await handlers.get("session_info_changed")({ name: "Background conversation" }, ctx);
});
assert.equal(calls.some((call) => call.command === "tmux-agent-subject"), false, "non-TTY session_info_changed does not update the interactive pane subject");

calls.length = 0;
await withStdoutTTY(true, async () => {
  await handlers.get("session_info_changed")({ name: "Updated conversation" }, ctx);
});
assert.deepEqual(calls.at(-1), {
  command: "tmux-agent-subject",
  args: ["set", "Updated conversation"],
}, "interactive session_info_changed renames the subject");

subjectApplyResult = fail();
const subjectApplyWarnings = [];
const originalSubjectApplyWarn = console.warn;
let subjectApplyTimeout;
console.warn = (...args) => subjectApplyWarnings.push(args);
try {
  const result = await Promise.race([
    withStdoutTTY(true, () => handlers.get("session_info_changed")({ name: "Failed update" }, ctx)).then(() => "returned"),
    new Promise((resolve) => {
      subjectApplyTimeout = setTimeout(() => resolve("blocked"), 100);
    }),
  ]);
  assert.equal(result, "returned", "nonzero tmux-agent-subject does not throw or block session_info_changed");
} finally {
  clearTimeout(subjectApplyTimeout);
  console.warn = originalSubjectApplyWarn;
  subjectApplyResult = ok();
}
assert.deepEqual(subjectApplyWarnings, [
  ["[managed-hooks] tmux-agent-subject set failed", { code: 1, killed: false }],
], "nonzero tmux-agent-subject emits safe diagnostics");

calls.length = 0;
await handlers.get("session_info_changed")({ name: undefined }, ctx);
assert.equal(calls.some((call) => call.command === "tmux-agent-subject"), false, "missing session_info_changed name does not rename the subject");

taskStatus = "provisional\tagent\tInvestigate reviewer failures\n";
currentSessionName = "";
managedPiSessionName = "";
windowLabel = "~ Investigate reviewer failures";
sessionNames.length = 0;
calls.length = 0;
const sessionInfoChanged = handlers.get("session_info_changed");
const originalSetSessionName = pi.setSessionName;
const provisionalSessionInfoChanges = [];
const provisionalSessionInfoChangedCalls = [];
pi.setSessionName = (name) => {
  provisionalSessionInfoChanges.push(name);
  originalSetSessionName(name);
  provisionalSessionInfoChangedCalls.push(sessionInfoChanged({ name }, ctx));
};
try {
  await withStdoutTTY(true, async () => {
    await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
    await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
    await flushAsyncWork();
    await Promise.all(provisionalSessionInfoChangedCalls);
    await flushAsyncWork();
  });
  assert.deepEqual(provisionalSessionInfoChanges, [], "provisional rendered labels never become Pi session names");
  assert.equal(calls.some((call) => call.command === "tmux-agent-subject"), false, "provisional task sync never feeds back through session_info_changed");
  assert.equal(calls.filter((call) => (
    call.command === "tmux" && call.args.at(-1) === "@window-label"
  )).length, 0, "provisional task sync never reads the decorated window label");
} finally {
  pi.setSessionName = originalSetSessionName;
}

taskStatus = "";

windowLabel = "pi main-repo feature-work";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.deepEqual(sessionNames, ["feature-work"], "successful bash results set only the meaningful Pi session name");
assert.equal(managedPiSessionName, "feature-work", "managed Pi session names are marked in tmux pane state");

currentSessionName = "feature-work";
windowLabel = "pi main-repo feature-work";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
windowLabel = "pi main-repo reload-work";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.equal(currentSessionName, "reload-work", "marked managed Pi session names keep updating after state recovery");
assert.deepEqual(sessionNames, ["feature-work", "reload-work"], "state recovery allows subsequent managed rename");

currentSessionName = "manual investigation name";
windowLabel = "pi main-repo later-worktree";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.equal(currentSessionName, "manual investigation name", "manual Pi session names are not overwritten by managed tmux sync");
assert.deepEqual(sessionNames, ["feature-work", "reload-work"], "manual-name preservation does not call setSessionName again");

await handlers.get("tool_result")({ toolName: "read", isError: false }, ctx);
assert.deepEqual(sessionNames, ["feature-work", "reload-work"], "non-bash tool results do not resync session names");

await handlers.get("tool_result")({ toolName: "bash", isError: true }, ctx);
assert.deepEqual(sessionNames, ["feature-work", "reload-work"], "failed bash results do not resync session names");

for (const workflow of ["z-fix", "z-spec-first", "z-quick-pr"]) {
  const reminder = await handlers.get("before_agent_start")({
    prompt: `Use ${workflow} for this`,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, { cwd: "/repo" });
  assert.match(reminder?.message.content || "", /repo-start <branch>/, `${workflow} prompt on main gets repo-start reminder`);
}

branch = "feature";
taskStatus = "";
const subjectChildPrompts = [
  "@.env",
  "--model malicious",
  "improve tmux labels; printf injected",
];
for (const prompt of subjectChildPrompts) {
  calls.length = 0;
  subjectChildExecOptions = undefined;
  const automaticSubject = await handlers.get("before_agent_start")({
    prompt,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, { cwd: "/repo", signal: subjectSignal });
  assert.equal(automaticSubject, undefined, `${prompt} prompt adds no main-context reminder`);
  const childCall = calls.find((call) => call.command === "pi" && !isGoalChildArgs(call.args));
  assert.ok(childCall, `${prompt} invokes isolated Pi child`);
  assert.equal(modelArg(childCall), "openai-codex/gpt-5.4-mini");
  assert.deepEqual(childCall.args.slice(0, -1), [
    "--mode", "text",
    "--print",
    "--no-session",
    "--model", "openai-codex/gpt-5.4-mini",
    "--thinking", "off",
    "--no-tools",
    "--no-extensions",
    "--no-skills",
    "--no-prompt-templates",
    "--no-themes",
    "--no-context-files",
    "--no-approve",
    "--system-prompt", "Return one concise noun phrase describing the user's task. Output only the phrase on one line, with no quotes, prefix, or explanation.",
  ], "subject child disables context-bearing resources");
  assert.equal(childCall.args.at(-1), `Task: ${prompt}`, `${prompt} is passed as one framed argv value`);
  assert.equal(subjectChildExecOptions.cwd, "/repo/main-repo", "subject child runs from the resolved worktree cwd");
  assert.equal(subjectChildExecOptions.timeout, 15000, "subject child timeout is threaded through");
  assert.equal(subjectChildExecOptions.signal, subjectSignal, "subject child receives the before_agent_start cancellation signal");
  assert.deepEqual(calls.find((call) => call.command === "tmux-agent-subject"), {
    command: "tmux-agent-subject",
    args: ["set", "improve tmux labels"],
  }, `${prompt} keeps the validated child subject`);
}

await flushAsyncWork();
const subjectPromptSentinel = "prompt-sentinel-7f3c7b7f";
for (const [label, failureResult, failureError, expectedMetadata] of [
  [
    "thrown error",
    ok("unused\n"),
    Object.assign(new TypeError(`child unavailable ${subjectPromptSentinel}`), {
      code: "ERR_INVALID_ARG_VALUE",
      exitCode: 1,
      killed: false,
    }),
    { name: "TypeError", code: "ERR_INVALID_ARG_VALUE", exitCode: 1, killed: false },
  ],
  [
    "stderr failure",
    { stdout: "", stderr: `raw child stderr ${subjectPromptSentinel}`, code: 1, killed: true },
    undefined,
    { name: "SubjectChildResult", code: 1, exitCode: undefined, killed: true },
  ],
]) {
  subjectChildResult = failureResult;
  subjectChildError = failureError;
  taskStatus = "";
  branch = "feature";
  goalChildResults.push(ok("subject failure test goal\n"));
  calls.length = 0;
  const warnings = [];
  const originalWarn = console.warn;
  console.warn = (...args) => warnings.push(args);
  try {
    const fallback = await handlers.get("before_agent_start")({
      prompt: `fallback ${label} ${subjectPromptSentinel}`,
      systemPrompt: "",
      systemPromptOptions: { cwd: "/repo" },
    }, { cwd: "/repo", signal: subjectSignal });
    assert.match(fallback.message.content, /tmux-agent-subject set/, `${label} child result preserves reminder fallback`);
  } finally {
    console.warn = originalWarn;
  }
  assert.equal(warnings.length > 0, true, `${label} child emits diagnostics`);
  assert.deepEqual(warnings[0], ["[managed-hooks] tmux subject child failed", expectedMetadata], `${label} child logs only safe metadata`);
  const warningText = warnings.flatMap((args) => args.map((arg) => (typeof arg === "string" ? arg : JSON.stringify(arg)))).join("\n");
  assert.equal(warningText.includes(subjectPromptSentinel), false, `${label} child diagnostics do not echo the prompt`);
}

subjectChildResult = ok("start another task\n");
taskStatus = "completed\tbranch\told-task\n";
calls.length = 0;
const completedAutomaticSubject = await handlers.get("before_agent_start")({
  prompt: "start another task",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.equal(completedAutomaticSubject, undefined, "completed task is automatically relabeled");
assert.ok(calls.some((call) => call.command === "pi" && !isGoalChildArgs(call.args)), "completed task invokes isolated Pi child");

for (const state of ["provisional\tagent\tshort subject\n", "active\tbranch\tfeature/current\n"]) {
  taskStatus = state;
  calls.length = 0;
  const currentTaskResult = await handlers.get("before_agent_start")({
    prompt: "continue current work",
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, { cwd: "/repo" });
  assert.equal(currentTaskResult, undefined, `${state.split("\t")[0]} task skips subject reminder`);
  assert.equal(calls.some((call) => call.command === "pi" && !isGoalChildArgs(call.args)), false, `${state.split("\t")[0]} task skips subject child`);
}

taskStatus = "active\tbranch\tfeature/current\n";
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "persistent Pi session goals" } },
];
await handlers.get("session_start")({ reason: "resume" }, ctx);

const assistantPrefix = "x".repeat(900);
const expectedAssistantTail = `${assistantPrefix}\nChoose one:\nA. Keep it\nB. Pause\nC. Continue`.slice(-800);
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "persistent Pi session goals" } },
  {
    type: "message",
    message: {
      role: "assistant",
      content: [
        { type: "text", text: assistantPrefix },
        { type: "thinking", thinking: "private reasoning" },
        { type: "toolCall", id: "call-1", name: "read", arguments: {} },
        { type: "text", text: "Choose one:\nA. Keep it\nB. Pause\nC. Continue" },
      ],
    },
  },
];
goalChildCalls.length = 0;
goalChildDeferred = deferred();
const entriesBeforeChoice = customEntries.length;
const namesBeforeChoice = sessionNames.length;
const nonblocking = handlers.get("before_agent_start")({
  prompt: "C",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
assert.equal(await Promise.race([
  nonblocking.then(() => "returned"),
  new Promise((resolve) => setTimeout(() => resolve("blocked"), 25)),
]), "returned", "goal evaluation does not block before_agent_start");
assert.equal(goalChildCalls.length, 1, "every expanded prompt starts goal evaluation");
assert.equal(modelArg(goalChildCalls.at(-1)), "openai-codex/gpt-5.4-mini");
assert.equal(authReadCount, 1, "unchanged auth metadata reuses parsed selection");
assert.deepEqual(goalChildCalls[0].args.slice(0, -1), [
  "--mode", "text",
  "--print",
  "--no-session",
  "--model", "openai-codex/gpt-5.4-mini",
  "--thinking", "off",
  "--no-tools",
  "--no-extensions",
  "--no-skills",
  "--no-prompt-templates",
  "--no-themes",
  "--no-context-files",
  "--no-approve",
  "--system-prompt", "Track the session's broad goal. Use the preceding assistant context to interpret the newest user prompt. Replies that answer, select from, approve, or continue the preceding assistant message should return KEEP when they remain within the current broad goal. Given the current goal and newest user prompt, return KEEP when the broad goal is unchanged. Otherwise return one concise noun phrase of at most 80 characters. Output only KEEP or the phrase on one line, without quotes, a goal: prefix, or explanation.",
], "goal child uses the exact isolated model and context arguments");
assert.equal(
  goalChildCalls[0].args.at(-1),
  `Current goal: persistent Pi session goals\nPreceding assistant context: ${expectedAssistantTail}\nNew user prompt: C`,
  "goal child receives bounded preceding assistant context for a choice reply",
);
assert.equal(goalChildCalls[0].args.at(-1).includes("private reasoning"), false, "goal context excludes thinking blocks");
assert.equal(goalChildCalls[0].args.at(-1).includes("call-1"), false, "goal context excludes tool-call blocks");
assert.equal(goalChildCalls[0].options.timeout, 15000, "goal child uses the bounded timeout");

goalChildDeferred.resolve(ok("KEEP\n"));
goalChildDeferred = undefined;
await flushAsyncWork();
assert.equal(customEntries.length, entriesBeforeChoice, "choice reply keeps the existing broad goal");
assert.equal(sessionNames.length, namesBeforeChoice, "choice reply does not rename the managed session");

branchEntries = [];
goalChildResults.push(ok("KEEP\n"));
await handlers.get("before_agent_start")({
  prompt: "initial task",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.match(goalChildCalls.at(-1).args.at(-1), /Preceding assistant context: \(none\)/, "missing assistant context is explicit");

branchEntries = [{
  type: "message",
  message: {
    role: "assistant",
    content: [
      { type: "text", text: "   " },
      { type: "text", text: "" },
      { type: "text", text: "\n\t" },
    ],
  },
}];
goalChildResults.push(ok("KEEP\n"));
await handlers.get("before_agent_start")({
  prompt: "whitespace task",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(
  goalChildCalls.at(-1).args.at(-1),
  "Current goal: persistent Pi session goals\nPreceding assistant context: (none)\nNew user prompt: whitespace task",
  "whitespace-only assistant text collapses to no context",
);

branchEntries = [{
  type: "message",
  message: { role: "assistant", content: [{ type: "text", text: "Should I proceed?" }] },
}];
goalChildResults.push(ok("renamed broad goal\n"));
await handlers.get("before_agent_start")({
  prompt: "Actually, switch to a different broad goal",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(customEntries.at(-1).data.subject, "renamed broad goal", "explicit redirect still updates the goal");

async function callGoalChildForManagedModel(prompt) {
  goalChildResults.push(ok("KEEP\n"));
  await handlers.get("before_agent_start")({
    prompt,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
  return goalChildCalls.at(-1);
}

const originalHomeAuthReads = authReadCount;
const originalOverrideAuthReads = overrideAuthReadCount;
const originalTildeAuthReads = tildeAuthReadCount;
const originalExactTildeAuthReads = exactTildeAuthReadCount;
const originalCodingAgentDirSetting = process.env.PI_CODING_AGENT_DIR;
try {
  replaceManagedChildAuth({
    "openai-codex": { type: "api_key", key: "home-key" },
  });
  fs.mkdirSync(managedChildOverrideAuthDir, { recursive: true });
  fs.writeFileSync(managedChildOverrideAuthPath, JSON.stringify(completeCodexOAuth));
  process.env.PI_CODING_AGENT_DIR = managedChildOverrideAuthDir;
  const callWithConfigDirOverride = await callGoalChildForManagedModel("config dir override");
  assert.equal(modelArg(callWithConfigDirOverride), "openai-codex/gpt-5.4-mini");
  assert.equal(authReadCount, originalHomeAuthReads, "HOME auth is not inspected when PI_CODING_AGENT_DIR is set");
  assert.equal(overrideAuthReadCount, originalOverrideAuthReads + 1, "config-dir auth is inspected when PI_CODING_AGENT_DIR is set");

  replaceManagedChildAuth({
    "openai-codex": { type: "api_key", key: "home-key" },
  });
  fs.mkdirSync(managedChildTildeAuthDir, { recursive: true });
  fs.writeFileSync(managedChildTildeAuthPath, JSON.stringify(completeCodexOAuth));
  process.env.PI_CODING_AGENT_DIR = "~/.pi-tilde/agent";
  const callWithTildeConfigDirOverride = await callGoalChildForManagedModel("config dir tilde override");
  assert.equal(modelArg(callWithTildeConfigDirOverride), "openai-codex/gpt-5.4-mini");
  assert.equal(authReadCount, originalHomeAuthReads, "HOME auth is not inspected when PI_CODING_AGENT_DIR uses a tilde path");
  assert.equal(tildeAuthReadCount, originalTildeAuthReads + 1, "tilde-expanded auth is inspected when PI_CODING_AGENT_DIR uses a tilde path");

  replaceManagedChildAuth({
    "openai-codex": { type: "api_key", key: "home-key" },
  });
  fs.writeFileSync(managedChildExactTildeAuthPath, JSON.stringify(completeCodexOAuth));
  process.env.PI_CODING_AGENT_DIR = "~";
  const callWithExactTildeConfigDirOverride = await callGoalChildForManagedModel("config dir exact tilde override");
  assert.equal(modelArg(callWithExactTildeConfigDirOverride), "openai-codex/gpt-5.4-mini");
  assert.equal(authReadCount, originalHomeAuthReads, "HOME auth is not inspected when PI_CODING_AGENT_DIR is exactly tilde");
  assert.equal(exactTildeAuthReadCount, originalExactTildeAuthReads + 1, "HOME auth.json is inspected when PI_CODING_AGENT_DIR is exactly tilde");

  fs.writeFileSync(managedChildOverrideAuthPath, JSON.stringify(completeCodexOAuth));
  fs.writeFileSync(managedChildTildeAuthPath, JSON.stringify({
    "openai-codex": { type: "api_key", key: "other-config-key" },
  }));
  useMatchingAuthMetadata = true;
  process.env.PI_CODING_AGENT_DIR = managedChildOverrideAuthDir;
  const callFromFirstMatchingMetadataPath = await callGoalChildForManagedModel("first matching metadata path");
  assert.equal(modelArg(callFromFirstMatchingMetadataPath), "openai-codex/gpt-5.4-mini");
  process.env.PI_CODING_AGENT_DIR = "~/.pi-tilde/agent";
  const callFromSecondMatchingMetadataPath = await callGoalChildForManagedModel("second matching metadata path");
  assert.equal(modelArg(callFromSecondMatchingMetadataPath), "openai/gpt-4.1-mini", "auth path participates in the cache key");
} finally {
  useMatchingAuthMetadata = false;
  if (originalCodingAgentDirSetting === undefined) delete process.env.PI_CODING_AGENT_DIR;
  else process.env.PI_CODING_AGENT_DIR = originalCodingAgentDirSetting;
  replaceManagedChildAuth(completeCodexOAuth);
}

removeManagedChildAuth();
const callAfterAuthRemoval = await callGoalChildForManagedModel("auth removed");
assert.equal(modelArg(callAfterAuthRemoval), "openai/gpt-4.1-mini");

writeManagedChildAuth(completeCodexOAuth);
chmodManagedChildAuth(0o600);
failManagedChildAuthRead = true;
const callAfterUnreadableAuth = await callGoalChildForManagedModel("auth unreadable");
failManagedChildAuthRead = false;
assert.equal(modelArg(callAfterUnreadableAuth), "openai/gpt-4.1-mini");

replaceManagedChildAuth("{malformed");
const callAfterMalformedAuth = await callGoalChildForManagedModel("auth malformed");
assert.equal(modelArg(callAfterMalformedAuth), "openai/gpt-4.1-mini");

replaceManagedChildAuth({
  "openai-codex": { type: "oauth", access: "test-access" },
});
const callAfterIncompleteOAuth = await callGoalChildForManagedModel("oauth incomplete");
assert.equal(modelArg(callAfterIncompleteOAuth), "openai/gpt-4.1-mini");

replaceManagedChildAuth({
  "openai-codex": { type: "api_key", key: "test-key" },
});
const callAfterNonOAuthAuth = await callGoalChildForManagedModel("auth is not oauth");
assert.equal(modelArg(callAfterNonOAuthAuth), "openai/gpt-4.1-mini");

replaceManagedChildAuth(completeCodexOAuth);
const callAfterAtomicReplacement = await callGoalChildForManagedModel("auth atomically replaced");
assert.equal(modelArg(callAfterAtomicReplacement), "openai-codex/gpt-5.4-mini");

process.env.PI_MANAGED_CHILD_MODEL = "custom-provider/custom-model";
const callWithOverride = await callGoalChildForManagedModel("model override");
assert.equal(modelArg(callWithOverride), "custom-provider/custom-model");
delete process.env.PI_MANAGED_CHILD_MODEL;

const entriesAfterChange = customEntries.length;
goalChildResults.push(ok("KEEP\n"));
await handlers.get("before_agent_start")({
  prompt: "continue",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(customEntries.length, entriesAfterChange, "KEEP does not append duplicate state");

for (const invalidOutput of [
  "\n",
  "first\nsecond\n",
  "goal: prefixed\n",
  "\"quoted subject\"\n",
  "support \"dry run\" mode\n",
  `${"x".repeat(81)}\n`,
  "control\u0007subject\n",
]) {
  goalChildResults.push(ok(invalidOutput));
  await handlers.get("before_agent_start")({
    prompt: "invalid output case",
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
}
assert.equal(customEntries.length, entriesAfterChange, "invalid goal outputs are never persisted");

goalChildCalls.length = 0;
customEntries.length = 0;
goalChildDeferred = deferred();
await handlers.get("before_agent_start")({
  prompt: "first redirect",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await handlers.get("before_agent_start")({
  prompt: "second redirect",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await handlers.get("before_agent_start")({
  prompt: "final redirect",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
assert.equal(goalChildCalls.length, 1, "only one goal child runs concurrently");

goalChildResults.push(ok("final session theme\n"));
goalChildDeferred.resolve(ok("stale session theme\n"));
goalChildDeferred = undefined;
await flushAsyncWork();
assert.equal(goalChildCalls.length, 2, "rapid prompts collapse to one pending evaluation");
assert.match(goalChildCalls[1].args.at(-1), /New user prompt: final redirect/);
assert.equal(customEntries.some((entry) => entry.data.subject === "stale session theme"), false, "stale running output is discarded");
assert.equal(customEntries.at(-1).data.subject, "final session theme", "newest pending output applies");

taskStatus = "provisional\tagent\tstarting goal\n";
currentSessionName = "";
managedPiSessionName = "";
goalChildResults.push(ok("persistent session goal\n"));
await handlers.get("before_agent_start")({
  prompt: "build persistent session goal",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(currentSessionName, "persistent session goal", "goal names a managed session before branch creation");

currentSessionName = "manual investigation name";
managedPiSessionName = "persistent session goal";
goalChildResults.push(ok("revised persistent goal\n"));
await handlers.get("before_agent_start")({
  prompt: "revise the persistent goal",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(currentSessionName, "manual investigation name", "manual name blocks automatic goal rename");
assert.equal(statuses.at(-1).value, "goal: revised persistent goal", "manual name does not block goal status updates");

currentSessionName = "persistent session goal";
managedPiSessionName = "persistent session goal";
taskStatus = "provisional\tagent\tstarting goal\n";
goalChildDeferred = deferred();
await handlers.get("before_agent_start")({
  prompt: "race with branch creation",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
taskStatus = "active\tbranch\tfeature/session-goal\n";
currentSessionName = "feature/session-goal";
managedPiSessionName = "feature/session-goal";
goalChildDeferred.resolve(ok("goal after branch\n"));
goalChildDeferred = undefined;
await flushAsyncWork();
assert.equal(currentSessionName, "feature/session-goal", "active branch wins a late goal naming race");
assert.equal(statuses.at(-1).value, "goal: goal after branch", "late goal still updates status after branch creation");

currentSessionName = "feature/existing";
managedPiSessionName = "feature/existing";
windowLabel = "pi main-repo feature/existing";
taskStatus = "active\tbranch\tfeature/existing\n";
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "branch goal" } },
];
await handlers.get("session_start")({ reason: "managed branch" }, ctx);
taskStatusFails = true;
goalChildResults.push(ok("goal during status failure\n"));
await handlers.get("before_agent_start")({
  prompt: "update goal while status is unavailable",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(currentSessionName, "feature/existing", "tmux status failure preserves an existing managed branch name");
assert.equal(statuses.at(-1).value, "goal: goal during status failure", "tmux status failure does not block goal status updates");
taskStatusFails = false;
taskStatus = "active\tbranch\tfeature/existing\n";

const freshHandlers = new Map();
const freshPi = {
  ...pi,
  on(event, handler) {
    freshHandlers.set(event, handler);
  },
};
const freshModuleUrl = `${pathToFileURL(extensionPath).href}?fresh-managed-name-recovery`;
const { default: installFresh } = await import(freshModuleUrl);
installFresh(freshPi);

branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "evolved goal G" } },
];
currentSessionName = "evolved goal G";
managedPiSessionName = "evolved goal G";
windowLabel = "pi main-repo provisional goal P";
taskStatus = "provisional\tagent\tprovisional goal P\n";
sessionNames.length = 0;
await freshHandlers.get("session_start")({ reason: "fresh resume" }, ctx);
assert.equal(currentSessionName, "evolved goal G", "fresh resume keeps the restored evolving goal over a stale provisional tmux label");
assert.deepEqual(sessionNames, [], "fresh resume recognizes the marker-matched current goal without renaming it");
goalChildResults.push(ok("new goal H\n"));
await freshHandlers.get("before_agent_start")({
  prompt: "redirect to a new goal",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
assert.equal(currentSessionName, "new goal H", "fresh instances recover marker ownership and automatically rename an evolved goal again");

branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "restored goal G" } },
];
currentSessionName = "restored goal G";
managedPiSessionName = "restored goal G";
windowLabel = "pi main-repo provisional goal P";
taskStatus = "active\tbranch\tfeature/canonical-branch\n";
sessionNames.length = 0;
await freshHandlers.get("session_start")({ reason: "branch resume" }, ctx);
assert.equal(currentSessionName, "feature/canonical-branch", "verified active branch wins startup naming over restored goal and stale provisional label");
assert.deepEqual(sessionNames, ["feature/canonical-branch"], "startup names directly from canonical active branch status");

currentSessionName = "";
managedPiSessionName = "restored goal G";
taskStatusFails = true;
sessionNames.length = 0;
await freshHandlers.get("session_start")({ reason: "status failure resume" }, ctx);
assert.equal(currentSessionName, "", "startup status failure fails closed instead of naming from the restored goal");
assert.deepEqual(sessionNames, [], "startup status failure performs no speculative session-name side effect");
taskStatusFails = false;
taskStatus = "active\tbranch\tfeature/existing\n";

await handlers.get("session_start")({ reason: "failure reset" }, ctx);
notifications.length = 0;
for (let failure = 1; failure <= 13; failure += 1) {
  goalChildResults.push(fail());
  await handlers.get("before_agent_start")({
    prompt: `failure ${failure}`,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
}
assert.deepEqual(notifications.map((item) => item.message), [
  "Session goal updates are failing; keeping the previous goal.",
  "Session goal updates are failing; keeping the previous goal.",
], "repeated failures notify only at 3 and 13");

notifications.length = 0;
goalChildResults.push(ok("KEEP\n"), fail(), fail(), fail());
for (const prompt of ["recover", "again 1", "again 2", "again 3"]) {
  await handlers.get("before_agent_start")({
    prompt,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
}
assert.equal(notifications.length, 1, "successful KEEP resets the consecutive failure counter");

const goalPromptSentinel = "goal-prompt-sentinel-71b72b";
const goalStdoutSentinel = "goal-stdout-sentinel-0c23ff";
const goalWarnings = [];
const originalGoalWarn = console.warn;
console.warn = (...args) => goalWarnings.push(args);
try {
  goalChildErrors.push(Object.assign(new TypeError(`child unavailable ${goalPromptSentinel}`), {
    code: "ERR_INVALID_ARG_VALUE",
    exitCode: 1,
    killed: false,
  }));
  await handlers.get("before_agent_start")({
    prompt: goalPromptSentinel,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
  goalChildResults.push({ stdout: goalStdoutSentinel, stderr: "raw stderr", code: 1, killed: false });
  await handlers.get("before_agent_start")({
    prompt: "failed child result",
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
} finally {
  console.warn = originalGoalWarn;
}
assert.deepEqual(goalWarnings, [
  ["[managed-hooks] session goal child failed", {
    name: "TypeError",
    code: "ERR_INVALID_ARG_VALUE",
    exitCode: 1,
    killed: false,
  }],
  ["[managed-hooks] session goal child failed", {
    name: "SessionGoalChildResult",
    code: 1,
    exitCode: undefined,
    killed: false,
  }],
], "goal child diagnostics contain only a fixed message and safe metadata");
const goalWarningText = goalWarnings.flatMap((args) => args.map((arg) => (
  typeof arg === "string" ? arg : JSON.stringify(arg)
))).join("\n");
assert.equal(goalWarningText.includes(goalPromptSentinel), false, "goal diagnostics do not echo the prompt");
assert.equal(goalWarningText.includes(goalStdoutSentinel), false, "goal diagnostics do not echo raw stdout");

const lifecycleGoalCallStart = goalChildCalls.length;
maxActiveGoalChildren = activeGoalChildren;
goalChildIgnoresAbort = true;
goalChildDeferred = deferred();
const oldSessionGoalDeferred = goalChildDeferred;
const lifecycleWarnings = [];
const originalLifecycleWarn = console.warn;
console.warn = (...args) => lifecycleWarnings.push(args);
await handlers.get("before_agent_start")({
  prompt: "old session prompt",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
goalChildDeferred = undefined;
await handlers.get("session_shutdown")({ reason: "resume" }, ctx);
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "destination goal" } },
];
await handlers.get("session_start")({ reason: "resume" }, ctx);
assert.equal(statuses.at(-1).value, "goal: destination goal", "replacement session restores its durable goal before new evaluation");
goalChildResults.push(ok("replacement session goal\n"));
await handlers.get("before_agent_start")({
  prompt: "replacement session prompt",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
const goalCallsBeforeOldSettlement = goalChildCalls.length;
goalChildIgnoresAbort = false;
oldSessionGoalDeferred.resolve({ stdout: "stale old goal\n", stderr: "", code: 1, killed: true });
await flushAsyncWork();
console.warn = originalLifecycleWarn;
assert.equal(maxActiveGoalChildren, 1, "replacement session never overlaps the settling aborted goal child");
assert.equal(goalCallsBeforeOldSettlement, lifecycleGoalCallStart + 1, "replacement goal waits for the old child to settle");
assert.equal(goalChildCalls.length, lifecycleGoalCallStart + 2, "newest replacement request runs after old settlement");
assert.match(goalChildCalls.at(-1).args.at(-1), /New user prompt: replacement session prompt/);
assert.equal(customEntries.some((entry) => entry.data.subject === "stale old goal"), false, "shutdown prevents stale goal application");
assert.equal(statuses.at(-1).value, "goal: replacement session goal", "replacement request applies after old settlement");
assert.equal(lifecycleWarnings.some((args) => args[0] === "[managed-hooks] session goal child failed"), false, "shutdown abort emits no goal failure warning");

const treeGoalCallStart = goalChildCalls.length;
maxActiveGoalChildren = activeGoalChildren;
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "source branch goal" } },
];
await handlers.get("session_tree")({ reason: "navigate" }, ctx);
goalChildIgnoresAbort = true;
goalChildDeferred = deferred();
const sourceBranchDeferred = goalChildDeferred;
await handlers.get("before_agent_start")({
  prompt: "source branch pending prompt",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
goalChildDeferred = undefined;
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "destination branch goal" } },
];
await handlers.get("session_tree")({ reason: "navigate" }, ctx);
assert.equal(statuses.at(-1).value, "goal: destination branch goal", "tree navigation immediately restores the destination branch goal");
goalChildResults.push(ok("destination branch evaluated goal\n"));
await handlers.get("before_agent_start")({
  prompt: "destination branch prompt",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
const treeCallsBeforeOldSettlement = goalChildCalls.length;
goalChildIgnoresAbort = false;
sourceBranchDeferred.resolve(ok("stale source branch goal\n"));
await flushAsyncWork();
assert.equal(maxActiveGoalChildren, 1, "tree navigation never overlaps the settling old evaluator");
assert.equal(treeCallsBeforeOldSettlement, treeGoalCallStart + 1, "destination evaluator waits for the old branch child to settle");
assert.equal(goalChildCalls.length, treeGoalCallStart + 2, "destination evaluator starts after old branch settlement");
assert.equal(customEntries.some((entry) => entry.data.subject === "stale source branch goal"), false, "tree navigation discards stale old-branch output");
assert.equal(statuses.at(-1).value, "goal: destination branch evaluated goal", "destination branch evaluation applies after old settlement");

currentSessionName = "";
managedPiSessionName = "";
taskStatusDeferred = deferred();
goalChildResults.push(ok("stale pre-navigation goal\n"));
const preNavigationHook = handlers.get("before_agent_start")({
  prompt: "rename before navigation",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await flushAsyncWork();
branchEntries = [
  { type: "custom", customType: "session-goal", data: { subject: "post-navigation destination goal" } },
];
await handlers.get("session_tree")({ reason: "navigate during status" }, ctx);
taskStatusDeferred.resolve(ok("provisional\tagent\tstarting goal\n"));
await preNavigationHook;
taskStatusDeferred = undefined;
await flushAsyncWork();
assert.equal(currentSessionName, "", "a request invalidated while canonical status is pending cannot rename the destination session");
assert.equal(statuses.at(-1).value, "goal: post-navigation destination goal", "status-query race preserves the destination branch goal");

notifications.length = 0;
const entriesBeforePersistenceFailures = customEntries.length;
const goalBeforePersistenceFailures = statuses.at(-1).value;
appendEntryErrors.push(
  new Error("persistence unavailable"),
  new Error("persistence unavailable"),
  new Error("persistence unavailable"),
);
for (const subject of ["unpersisted goal one", "unpersisted goal two", "unpersisted goal three"]) {
  goalChildResults.push(ok(`${subject}\n`));
  await handlers.get("before_agent_start")({
    prompt: `try ${subject}`,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, ctx);
  await flushAsyncWork();
}
assert.equal(customEntries.length, entriesBeforePersistenceFailures, "persistence failures do not append partial goal entries");
assert.equal(statuses.at(-1).value, goalBeforePersistenceFailures, "persistence failures preserve the previous in-memory goal");
assert.equal(notifications.length, 1, "repeated persistence failures use goal failure warnings");

taskStatus = "";
for (const [name, result] of [
  ["empty", ok("\n")],
  ["multiline", ok("first line\nsecond line\n")],
  ["oversized", ok(`${"x".repeat(513)}\n`)],
  ["failed", fail()],
  ["timed out", { stdout: "", stderr: "", code: 1, killed: true }],
]) {
  subjectChildResult = result;
  subjectChildError = undefined;
  calls.length = 0;
  const fallback = await handlers.get("before_agent_start")({
    prompt: `fallback ${name}`,
    systemPrompt: "",
    systemPromptOptions: { cwd: "/repo" },
  }, { cwd: "/repo" });
  assert.match(fallback.message.content, /tmux-agent-subject set/, `${name} child result preserves reminder fallback`);
  assert.equal(calls.some((call) => call.command === "tmux-agent-subject"), false, `${name} child result is not applied`);
}

subjectChildResult = ok("valid subject\n");
subjectApplyResult = fail();
taskStatus = "";
calls.length = 0;
const applyFallback = await handlers.get("before_agent_start")({
  prompt: "fallback apply failure",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.match(applyFallback.message.content, /tmux-agent-subject set/, "subject apply failure preserves reminder fallback");
subjectApplyResult = ok();

subjectChildResult = ok("unused\n");
subjectChildError = new Error("child unavailable");
taskStatus = "";
calls.length = 0;
const thrownFallback = await handlers.get("before_agent_start")({
  prompt: "fallback thrown error",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.match(thrownFallback.message.content, /tmux-agent-subject set/, "thrown child error preserves reminder fallback");
subjectChildError = undefined;

taskStatus = "";
branch = "main";

const worktreeBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git worktree add ../x" },
}, { cwd: "/repo" });
assert.equal(worktreeBlock.block, true, "blocks direct git worktree add");
assert.match(worktreeBlock.reason, /repo-start/, "worktree block points to repo-start");

const branchBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git switch -c new-branch" },
}, { cwd: "/repo" });
assert.equal(branchBlock.block, true, "blocks direct branch creation");

const gitOptionWorktreeBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "command git -C /repo worktree remove ../x" },
}, { cwd: "/repo" });
assert.equal(gitOptionWorktreeBlock.block, true, "blocks git -C worktree commands");
assert.match(gitOptionWorktreeBlock.reason, /repo-end/, "worktree remove block points to repo-end");

const branchMoveBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "env X=1 git -C /repo branch -m old new" },
}, { cwd: "/repo" });
assert.equal(branchMoveBlock.block, true, "blocks branch mutation options");

const branchList = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git branch --list feature" },
}, { cwd: "/repo" });
assert.equal(branchList, undefined, "allows branch list commands");

const commitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git commit -m test" },
}, { cwd: "/repo" });
assert.equal(commitBlock.block, true, "blocks raw git commit");
assert.match(commitBlock.reason, /z-commit/, "commit block points to z-commit skill");

const commitHelper = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "bash ~/.local/share/skills/_commit/commit.sh message" },
}, { cwd: "/repo" });
assert.equal(commitHelper, undefined, "allows _commit helper handoff");

const commitWithHelperTokenBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git commit -m test; echo commit.sh" },
}, { cwd: "/repo" });
assert.equal(commitWithHelperTokenBlock.block, true, "blocks raw git commit even when another segment mentions commit.sh");

const multilineCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "echo ok\ngit commit -m test" },
}, { cwd: "/repo" });
assert.equal(multilineCommitBlock.block, true, "blocks raw git commit on a later shell line");

const sudoCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "sudo git commit -m test" },
}, { cwd: "/repo" });
assert.equal(sudoCommitBlock.block, true, "blocks sudo-prefixed raw git commit");

const timedCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "time git commit -m test" },
}, { cwd: "/repo" });
assert.equal(timedCommitBlock.block, true, "blocks time-prefixed raw git commit");

const sudoOptionCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "sudo -E git commit -m test" },
}, { cwd: "/repo" });
assert.equal(sudoOptionCommitBlock.block, true, "blocks sudo-option-prefixed raw git commit");

const shellWrappedCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "bash -c 'git commit -m test'" },
}, { cwd: "/repo" });
assert.equal(shellWrappedCommitBlock.block, true, "blocks raw git commit inside bash -c");

const shellWrappedLoginCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "bash -lc 'git commit -m test'" },
}, { cwd: "/repo" });
assert.equal(shellWrappedLoginCommitBlock.block, true, "blocks raw git commit inside bash -lc");

const absoluteShellWrappedCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "/bin/bash -lc 'git commit -m test'" },
}, { cwd: "/repo" });
assert.equal(absoluteShellWrappedCommitBlock.block, true, "blocks raw git commit inside absolute bash wrapper");

const sudoShellWrappedCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "sudo bash -c 'git commit -m test'" },
}, { cwd: "/repo" });
assert.equal(sudoShellWrappedCommitBlock.block, true, "blocks raw git commit inside sudo shell wrapper");

const sudoOptionShellWrappedCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "sudo -E bash -c 'git commit -m test'" },
}, { cwd: "/repo" });
assert.equal(sudoOptionShellWrappedCommitBlock.block, true, "blocks raw git commit inside sudo-option shell wrapper");

const shellWrappedTrailingArgCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "bash -c 'git commit -m test' dummy" },
}, { cwd: "/repo" });
assert.equal(shellWrappedTrailingArgCommitBlock.block, true, "blocks raw git commit inside bash -c with trailing argv");

const shellWrappedSemicolonCommitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "bash -c 'cd /repo; git commit -m test'" },
}, { cwd: "/repo" });
assert.equal(shellWrappedSemicolonCommitBlock.block, true, "blocks raw git commit after semicolon inside quoted shell payload");

const pushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push origin HEAD:main" },
}, { cwd: "/repo" });
assert.equal(pushMainBlock.block, true, "blocks git push refspec targeting main");
assert.match(pushMainBlock.reason, /push to main/, "push-main block explains direct main push");

const timedPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "time git push origin HEAD:main" },
}, { cwd: "/repo" });
assert.equal(timedPushMainBlock.block, true, "blocks time-prefixed git push to main");

const timedOptionPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "time -p git push origin HEAD:main" },
}, { cwd: "/repo" });
assert.equal(timedOptionPushMainBlock.block, true, "blocks time-option-prefixed git push to main");

const timedShellWrappedPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "time sh -c 'git push origin HEAD:main'" },
}, { cwd: "/repo" });
assert.equal(timedShellWrappedPushMainBlock.block, true, "blocks git push to main inside time shell wrapper");

const timedOptionShellWrappedPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "time -p sh -c 'git push origin HEAD:main'" },
}, { cwd: "/repo" });
assert.equal(timedOptionShellWrappedPushMainBlock.block, true, "blocks git push to main inside time-option shell wrapper");

const shellWrappedPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "sh -c 'git push origin HEAD:main'" },
}, { cwd: "/repo" });
assert.equal(shellWrappedPushMainBlock.block, true, "blocks git push to main inside sh -c");

const shellWrappedLoginPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "zsh -lc 'git push origin HEAD:main'" },
}, { cwd: "/repo" });
assert.equal(shellWrappedLoginPushMainBlock.block, true, "blocks git push to main inside zsh -lc");

const absoluteShellWrappedPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "/usr/bin/zsh -c 'git push origin HEAD:main'" },
}, { cwd: "/repo" });
assert.equal(absoluteShellWrappedPushMainBlock.block, true, "blocks git push to main inside absolute zsh wrapper");

const pushDeleteMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push origin :main" },
}, { cwd: "/repo" });
assert.equal(pushDeleteMainBlock.block, true, "blocks delete refspec targeting main");

const pushMatchingBranchesBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push origin :" },
}, { cwd: "/repo" });
assert.equal(pushMatchingBranchesBlock.block, true, "blocks matching-branches push because it can update main");

const pushForceMatchingBranchesBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push origin +:" },
}, { cwd: "/repo" });
assert.equal(pushForceMatchingBranchesBlock.block, true, "blocks forced matching-branches push because it can update main");

const multilinePushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "echo ok\ngit push origin HEAD:main" },
}, { cwd: "/repo" });
assert.equal(multilinePushMainBlock.block, true, "blocks git push to main on a later shell line");

const implicitPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push" },
}, { cwd: "/repo" });
assert.equal(implicitPushMainBlock.block, true, "blocks implicit push while current branch is main");

const headPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push origin HEAD" },
}, { cwd: "/repo" });
assert.equal(headPushMainBlock.block, true, "blocks HEAD push while current branch is main");

const upstreamHeadPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push -u origin HEAD" },
}, { cwd: "/repo" });
assert.equal(upstreamHeadPushMainBlock.block, true, "blocks upstream HEAD push while current branch is main");

const headPushWithOptionOperandMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push -o ci.skip origin HEAD" },
}, { cwd: "/repo" });
assert.equal(headPushWithOptionOperandMainBlock.block, true, "blocks HEAD push with push-option operand while current branch is main");

const implicitPushWithOptionOperandMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push -o ci.skip origin" },
}, { cwd: "/repo" });
assert.equal(implicitPushWithOptionOperandMainBlock.block, true, "blocks implicit push with push-option operand while current branch is main");

const headPushWithTrailingOptionMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push origin HEAD --force" },
}, { cwd: "/repo" });
assert.equal(headPushWithTrailingOptionMainBlock.block, true, "blocks HEAD push with trailing options while current branch is main");

const chainedImplicitPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push && echo done" },
}, { cwd: "/repo" });
assert.equal(chainedImplicitPushMainBlock.block, true, "blocks implicit push to main in compound commands");

branch = "feature";
const implicitPushFeature = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push" },
}, { cwd: "/repo" });
assert.equal(implicitPushFeature, undefined, "allows implicit push off main");
branch = "main";
const gitCImplicitPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git -C /repo push" },
}, { cwd: worktreeRoot });
assert.equal(gitCImplicitPushMainBlock.block, true, "blocks implicit push to main in repo selected by git -C");

const quotedGitCImplicitPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git -C \"/repo\" push" },
}, { cwd: worktreeRoot });
assert.equal(quotedGitCImplicitPushMainBlock.block, true, "blocks implicit push to main in quoted repo selected by git -C");

const cdImplicitPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "cd /repo && git push" },
}, { cwd: worktreeRoot });
assert.equal(cdImplicitPushMainBlock.block, true, "blocks implicit push after cd into main repo");

const failedCdImplicitPushMainBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "cd /missing; git push" },
}, { cwd: "/repo" });
assert.equal(failedCdImplicitPushMainBlock.block, true, "blocks implicit push when prior cd target cannot be verified");

const orderedShellPayloadImplicitPushBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: `bash -c 'git push' && cd ${worktreeRoot}` },
}, { cwd: "/repo" });
assert.equal(orderedShellPayloadImplicitPushBlock.block, true, "checks shell payload before later top-level cwd changes");

const scopedShellPayloadImplicitPushBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: `bash -c 'cd ${worktreeRoot} && true'; git push` },
}, { cwd: "/repo" });
assert.equal(scopedShellPayloadImplicitPushBlock.block, true, "does not leak shell-wrapper cd into later parent implicit push");

const controlFlowCdImplicitPushBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: `false && cd ${worktreeRoot} || git push` },
}, { cwd: "/repo" });
assert.equal(controlFlowCdImplicitPushBlock.block, true, "keeps original cwd as possible context across shell control flow");

const pushAllBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push origin --all" },
}, { cwd: "/repo" });
assert.equal(pushAllBlock.block, true, "blocks push --all because it can update main");

const pushMirrorBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push --mirror origin" },
}, { cwd: "/repo" });
assert.equal(pushMirrorBlock.block, true, "blocks push --mirror because it can update main");

const pushTagsOnly = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push --tags" },
}, { cwd: "/repo" });
assert.equal(pushTagsOnly, undefined, "allows tags-only push on main");

const pushDryRun = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push --dry-run" },
}, { cwd: "/repo" });
assert.equal(pushDryRun, undefined, "allows dry-run push on main");

const pushFeature = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git push origin feature" },
}, { cwd: "/repo" });
assert.equal(pushFeature, undefined, "allows git push to non-main refs");

const forceAddBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git add -f docs/superpowers/specs/design.md" },
}, { cwd: "/repo" });
assert.equal(forceAddBlock.block, true, "blocks force-adding superpowers docs");
assert.match(forceAddBlock.reason, /docs\/superpowers/, "force-add block names superpowers docs");

const forceAddFromSuperpowersCwdBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "cd docs/superpowers/specs && git add -f design.md" },
}, { cwd: "/repo" });
assert.equal(forceAddFromSuperpowersCwdBlock.block, true, "blocks force-add from inside docs/superpowers cwd");

const forceAddRelativeSuperpowersBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "cd docs && git add -f superpowers/specs/design.md" },
}, { cwd: "/repo" });
assert.equal(forceAddRelativeSuperpowersBlock.block, true, "blocks force-add of relative path resolving into docs/superpowers");

const forceAddQuotedRelativeSuperpowersBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "cd docs && git add -f \"superpowers/specs/design.md\"" },
}, { cwd: "/repo" });
assert.equal(forceAddQuotedRelativeSuperpowersBlock.block, true, "blocks force-add of quoted relative path resolving into docs/superpowers");

const forceAddQuotedCdRelativeSuperpowersBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "cd \"docs\" && git add -f superpowers/specs/design.md" },
}, { cwd: "/repo" });
assert.equal(forceAddQuotedCdRelativeSuperpowersBlock.block, true, "blocks force-add after quoted cd target into docs");

const normalAdd = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git add docs/superpowers/specs/design.md" },
}, { cwd: "/repo" });
assert.equal(normalAdd, undefined, "allows non-force superpowers docs adds");

branch = "main";
const worktreeWrite = await handlers.get("tool_call")({
  toolName: "write",
  input: { path: path.join(worktreeRoot, "tests", "new-contract.rb"), content: "ok" },
}, { cwd: "/repo" });
assert.equal(worktreeWrite, undefined, "tracks feature-worktree writes even when session cwd is main");

branch = "feature";
const featureEdit = await handlers.get("tool_call")({
  toolName: "write",
  input: { path: "file", content: "ok" },
}, { cwd: "/repo" });
assert.equal(featureEdit, undefined, "allows edit/write tools off main");

agentWorktreePath = "";
await handlers.get("tool_call")({
  toolName: "write",
  input: { path: "docs/superpowers/specs/pi-managed-hooks-design.md", content: "# Design" },
}, { cwd: "/repo" });
assert.deepEqual(calls.at(-1), {
  command: "tmux",
  args: ["set-option", "-p", "-t", "%1", "@agent_current_spec_path", "/repo/docs/superpowers/specs/pi-managed-hooks-design.md"],
}, "tracks edited superpowers spec path in tmux pane state");

const externalSpecPath = path.join(worktreeRoot, "docs", "superpowers", "specs", "external-design.md");
fs.mkdirSync(path.dirname(externalSpecPath), { recursive: true });
await handlers.get("tool_call")({
  toolName: "write",
  input: { path: externalSpecPath, content: "# Design" },
}, { cwd: "/repo" });
assert.deepEqual(calls.at(-1), {
  command: "tmux",
  args: ["set-option", "-p", "-t", "%1", "@agent_current_spec_path", externalSpecPath],
}, "tracks absolute spec paths in the edited file's repo even when session cwd differs");

await handlers.get("tool_call")({
  toolName: "write",
  input: { path: "../docs/superpowers/specs/subdir-relative-design.md", content: "# Design" },
}, { cwd: path.join(worktreeRoot, "subdir") });
assert.deepEqual(calls.at(-1), {
  command: "tmux",
  args: ["set-option", "-p", "-t", "%1", "@agent_current_spec_path", path.join(worktreeRoot, "docs", "superpowers", "specs", "subdir-relative-design.md")],
}, "tracks write/edit spec paths relative to the tool cwd, not repo root");

const beforeMissingCommandResultSetOptions = calls.filter((call) => call.command === "tmux" && call.args.includes("@agent_current_spec_path")).length;
await handlers.get("tool_result")({
  toolName: "bash",
  isError: false,
}, { cwd: worktreeRoot });
const afterMissingCommandResultSetOptions = calls.filter((call) => call.command === "tmux" && call.args.includes("@agent_current_spec_path")).length;
assert.equal(afterMissingCommandResultSetOptions, beforeMissingCommandResultSetOptions, "ignores bash results without command input for current-spec tracking");

const bashSpecPath = path.join(worktreeRoot, "docs", "superpowers", "specs", "bash-created-design.md");
fs.mkdirSync(path.dirname(bashSpecPath), { recursive: true });
fs.writeFileSync(bashSpecPath, "# Design\n");
await handlers.get("tool_result")({
  toolName: "bash",
  input: { command: "cat > docs/superpowers/specs/bash-created-design.md <<'EOF'\n# Design\nEOF" },
  isError: false,
}, { cwd: worktreeRoot });
assert(calls.some((call) => call.command === "tmux" && JSON.stringify(call.args) === JSON.stringify(["set-option", "-p", "-t", "%1", "@agent_current_spec_path", bashSpecPath])), "tracks successful bash-created superpowers spec paths in tmux pane state");

restoreManagedChildTestState();
process.removeListener("exit", restoreManagedChildTestState);
console.log("pi-managed-hooks checks complete");
NODE

PI_HOOK_TEST_WORKTREE="$TMPROOT/worktree" "${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/managed-hooks.mjs"
