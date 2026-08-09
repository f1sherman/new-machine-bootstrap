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
const sessionNames = [];
let goalTool;
let currentSessionName = "";
let activeSessionFile = "/sessions/current.jsonl";
let branch = "main";
let taskStatus = "";
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
  async exec(command, args, options = {}) {
    calls.push({ command, args });
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
      return ok();
    }
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
  },
};

process.env.TMUX = "1";
process.env.TMUX_PANE = "%1";
const { default: install } = await import(pathToFileURL(extensionPath));
install(pi);

currentSessionName = "";
publishedIdentity = { source: "", subject: "" };
await handlers.get("session_start")({ reason: "resume" }, ctx);
assert.deepEqual(publishedIdentity, { source: "", subject: "" },
  "an unnamed resumed session does not replace the tmux fallback");
assert.equal(calls.some((call) => call.command === "tmux-update-pane-label"
  || call.command === "tmux-window-label"
  || (call.command === "tmux-agent-state" && call.args[0] === "set-kind")), false,
  "non-TTY session_start does not mutate tmux state");

currentSessionName = "restored session name";
await withStdoutTTY(() => handlers.get("session_start")({ reason: "resume" }, ctx));
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "restored session name",
}, "same-pane resume publishes the restored Pi session name");

await withStdoutTTY(() => goalTool.execute(
  "rename-session",
  { goal: "new broad name" },
  ctx.signal,
  undefined,
  ctx,
));
assert.equal(currentSessionName, "new broad name");
assert.deepEqual(publishedIdentity, {
  source: "manual",
  subject: "new broad name",
});
assert.equal(calls.some((call) => call.command === "tmux"
  && call.args.includes("@pi_managed_session_name")), false,
  "single-name flow does not use the old tmux ownership marker");

currentSessionName = "";
await withStdoutTTY(() => handlers.get("session_info_changed")({ name: "" }, ctx));
assert.equal(calls.some((call) => call.command === "tmux-agent-state"
  && call.args[0] === "clear-task"), true,
  "clearing a manual Pi name clears the published task");
assert.equal(calls.some((call) => call.command === "tmux-agent-worktree"
  && call.args[0] === "sync-current"), true,
  "clearing a manual Pi name restores worktree fallback state");


currentSessionName = "";
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
