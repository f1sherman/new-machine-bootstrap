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
import path from "node:path";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const worktreeRoot = process.env.PI_HOOK_TEST_WORKTREE;
const handlers = new Map();
const calls = [];
const entries = [];
const sessionNames = [];
let goalTool;
let currentSessionName = "";
let activeSessionFile = "/sessions/current.jsonl";
let branchEntries = [];
let branch = "main";
let managedSessionName = "";
let markerWriteDeferred;
let markerReadDeferred;
let activeMarkerWrites = 0;
let maxActiveMarkerWrites = 0;
let goalChildDeferred;
let goalChildIgnoresAbort = false;
let publishedIdentity = { source: "", subject: "" };
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
  const index = args.indexOf("--system-prompt");
  return index !== -1 && args[index + 1].includes("session's broad goal");
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
    if (definition.name === "set_session_goal") goalTool = definition;
  },
  setSessionName(name) {
    currentSessionName = name;
    sessionNames.push(name);
  },
  appendEntry(customType, data) {
    entries.push({ customType, data });
  },
  async exec(command, args, options = {}) {
    calls.push({ command, args });
    if (command === "tmux" && args[0] === "show-options") {
      if (args.at(-1) === "@pi_managed_session_name") {
        const wait = markerReadDeferred;
        markerReadDeferred = undefined;
        if (wait) await wait.promise;
        return managedSessionName ? ok(`${managedSessionName}\n`) : fail();
      }
      if (args.at(-1) === "@agent_worktree_path") return ok(`${worktreeRoot}\n`);
      if (args.at(-1) === "@window-label") return ok("pi main-repo\n");
      return fail();
    }
    if (command === "tmux" && args[0] === "set-option") {
      if (args.includes("@pi_managed_session_name")) {
        activeMarkerWrites += 1;
        maxActiveMarkerWrites = Math.max(maxActiveMarkerWrites, activeMarkerWrites);
        try {
          const wait = markerWriteDeferred;
          if (wait) await wait.promise;
          managedSessionName = args.at(-1);
        } finally {
          activeMarkerWrites -= 1;
        }
      }
      return ok();
    }
    if (command === "tmux-agent-state" && args[0] === "set-identity") {
      publishedIdentity = { source: args[1], subject: args[2] };
      return ok();
    }
    if (command === "tmux-agent-state" && args[0] === "status") return fail();
    if (command === "tmux-agent-state" || command.startsWith("tmux-")) return ok();
    if (command === "pi" && isGoalChild(args)) {
      if (!goalChildDeferred) return ok("generated goal\n");
      return goalChildIgnoresAbort
        ? goalChildDeferred.promise
        : abortable(goalChildDeferred.promise, options.signal);
    }
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
  ui: {
    theme: { fg(_color, value) { return value; } },
    setStatus() {},
  },
  sessionManager: {
    getSessionName() { return currentSessionName; },
    getSessionFile() { return activeSessionFile; },
    getBranch() { return branchEntries; },
  },
};

process.env.TMUX = "1";
process.env.TMUX_PANE = "%1";
const { default: install } = await import(pathToFileURL(extensionPath));
install(pi);

branchEntries = [];
await handlers.get("session_tree")({}, ctx);
goalChildIgnoresAbort = true;
goalChildDeferred = deferred();
const staleInitialGoal = goalChildDeferred;
await handlers.get("before_agent_start")({
  prompt: "initial evaluator prompt",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
await withStdoutTTY(() => goalTool.execute(
  "explicit-winner",
  { goal: "explicit race winner" },
  ctx.signal,
  undefined,
  ctx,
));
goalChildDeferred = undefined;
staleInitialGoal.resolve(ok("stale generated goal\n"));
goalChildIgnoresAbort = false;
await flushAsyncWork();
assert.equal(entries.some((entry) => entry.data.subject === "stale generated goal"), false,
  "stale asynchronous goal does not overwrite an explicit persisted goal");
assert.equal(entries.at(-1).data.subject, "explicit race winner");

branchEntries = [];
currentSessionName = "";
managedSessionName = "";
await handlers.get("session_tree")({}, ctx);
goalChildDeferred = undefined;
markerWriteDeferred = deferred();
maxActiveMarkerWrites = 0;
await withStdoutTTY(() => handlers.get("before_agent_start")({
  prompt: "slow automatic goal",
  systemPromptOptions: { cwd: "/repo" },
}, ctx));
await flushAsyncWork();
const explicitAfterAutomatic = withStdoutTTY(() => goalTool.execute(
  "serialized-explicit",
  { goal: "serialized explicit winner" },
  ctx.signal,
  undefined,
  ctx,
));
await flushAsyncWork();
assert.equal(maxActiveMarkerWrites, 1,
  "goal persistence serializes marker ownership writes");
const blockedMarkerWrite = markerWriteDeferred;
markerWriteDeferred = undefined;
blockedMarkerWrite.resolve();
await explicitAfterAutomatic;
await flushAsyncWork();
assert.equal(entries.at(-1).data.subject, "serialized explicit winner");
assert.equal(currentSessionName, "serialized explicit winner");
assert.equal(managedSessionName, "serialized explicit winner");

branchEntries = [];
currentSessionName = "";
managedSessionName = "";
await handlers.get("session_tree")({}, ctx);
markerWriteDeferred = deferred();
sessionNames.length = 0;
const automaticDuringRename = withStdoutTTY(() => goalTool.execute(
  "manual-rename-race",
  { goal: "durable automatic goal" },
  ctx.signal,
  undefined,
  ctx,
));
await flushAsyncWork();
currentSessionName = "manual name during persistence";
await withStdoutTTY(() => handlers.get("session_info_changed")({
  name: currentSessionName,
}, ctx));
const renameMarkerWrite = markerWriteDeferred;
markerWriteDeferred = undefined;
renameMarkerWrite.resolve();
await automaticDuringRename;
assert.equal(currentSessionName, "manual name during persistence",
  "manual rename wins while automatic marker persistence is pending");
assert.equal(sessionNames.length, 0,
  "pending automatic work does not rename over the manual owner");
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "manual name during persistence",
});

branchEntries = [{
  type: "custom",
  customType: "session-goal",
  data: { subject: "queued automatic goal" },
}];
currentSessionName = "queued automatic goal";
managedSessionName = "queued automatic goal";
await handlers.get("session_tree")({}, ctx);
markerReadDeferred = deferred();
const pausedMarkerRead = markerReadDeferred;
publishedIdentity = { source: "", subject: "" };
await withStdoutTTY(async () => {
  const staleAutomaticPublication = handlers.get("session_info_changed")({
    name: "queued automatic goal",
  }, ctx);
  await flushAsyncWork();
  currentSessionName = "new manual name";
  const manualPublication = handlers.get("session_info_changed")({
    name: "new manual name",
  }, ctx);
  pausedMarkerRead.resolve();
  await Promise.all([staleAutomaticPublication, manualPublication]);
});
assert.deepEqual(publishedIdentity, { source: "manual", subject: "new manual name" },
  "manual identity remains final after stale ownership classification resumes");
assert.equal(calls.some((call) => call.command === "tmux-agent-state"
  && call.args.join(" ") === "set-identity goal queued automatic goal"), false,
  "stale automatic ownership is not published");

branchEntries = [];
currentSessionName = "";
managedSessionName = "";
await handlers.get("session_tree")({}, ctx);
goalChildIgnoresAbort = true;
goalChildDeferred = deferred();
const abandonedGeneration = goalChildDeferred;
const entriesBeforeNavigation = entries.length;
await handlers.get("before_agent_start")({
  prompt: "source session prompt",
  systemPromptOptions: { cwd: "/repo" },
}, ctx);
branchEntries = [{
  type: "custom",
  customType: "session-goal",
  data: { subject: "destination goal" },
}];
activeSessionFile = "/sessions/destination.jsonl";
await handlers.get("session_tree")({}, ctx);
goalChildDeferred = undefined;
abandonedGeneration.resolve(ok("abandoned source goal\n"));
goalChildIgnoresAbort = false;
await flushAsyncWork();
assert.equal(entries.length, entriesBeforeNavigation,
  "tree navigation invalidates pending persistence from the prior session");

branch = "main";
const destructiveCases = [
  "git worktree add ../x",
  "command git -C /repo worktree remove ../x",
  "git switch -c new-branch",
  "env X=1 git -C /repo branch -m old new",
  "git commit -m test",
  "sudo -E git commit -m test",
  "bash -lc 'git commit -m test'",
  "echo ok; git commit -m test",
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
  "bash ~/.local/share/skills/_commit/commit.sh message",
  "git push --tags",
  "git push --dry-run",
  "git push origin feature",
  "git add docs/superpowers/specs/design.md",
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
