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
fs.mkdirSync(path.join(worktreeRoot, "tests"), { recursive: true });
const { default: install } = await import(pathToFileURL(extensionPath));

const handlers = new Map();
const calls = [];
let branch = "main";

const ok = (stdout = "") => ({ stdout, stderr: "", code: 0, killed: false });
const fail = () => ({ stdout: "", stderr: "", code: 1, killed: false });

const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
  async exec(command, args) {
    calls.push({ command, args });
    if (command === "tmux-agent-state") return ok();
    if (command === "tmux") return fail();
    if (command === "git" && args.includes("rev-parse")) {
      return ok(args.includes(path.join(worktreeRoot, "tests")) ? `${worktreeRoot}\n` : "/repo\n");
    }
    if (command === "git" && args.includes("branch")) {
      return ok(args.includes(worktreeRoot) ? "feature\n" : `${branch}\n`);
    }
    return fail();
  },
};

install(pi);
assert.equal(typeof handlers.get("session_start"), "function", "registers session_start hook");
assert.equal(typeof handlers.get("before_agent_start"), "function", "registers before_agent_start hook");
assert.equal(typeof handlers.get("tool_call"), "function", "registers tool_call hook");

process.env.TMUX = "1";
process.env.TMUX_PANE = "%1";
delete process.env.TMUX_AGENT_STATE_DIR;

await handlers.get("session_start")({}, { cwd: "/repo" });
assert.deepEqual(calls.at(-1), { command: "tmux-agent-state", args: ["set-kind", "pi"] }, "session_start binds pi tmux kind");

const reminder = await handlers.get("before_agent_start")({
  prompt: "Use _fix for this",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.match(reminder.message.content, /repo-start <branch>/, "main branch prompt gets repo-start reminder");

const subjectReminder = await handlers.get("before_agent_start")({
  prompt: "invoke superpowers:brainstorming",
  systemPrompt: "",
  systemPromptOptions: { cwd: "/repo" },
}, { cwd: "/repo" });
assert.match(subjectReminder.message.content, /tmux-agent-subject set/, "stale or missing subject gets subject reminder");

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

branch = "main";
const editBlock = await handlers.get("tool_call")({
  toolName: "edit",
  input: { path: "file", edits: [] },
}, { cwd: "/repo" });
assert.equal(editBlock.block, true, "blocks edit/write tools on main");

const worktreeWrite = await handlers.get("tool_call")({
  toolName: "write",
  input: { path: path.join(worktreeRoot, "tests", "new-contract.rb"), content: "ok" },
}, { cwd: "/repo" });
assert.equal(worktreeWrite, undefined, "allows write tools for absolute paths in a feature worktree even when session cwd is main");

const mainWrite = await handlers.get("tool_call")({
  toolName: "write",
  input: { path: "/repo/main-contract.rb", content: "no" },
}, { cwd: worktreeRoot });
assert.equal(mainWrite.block, true, "blocks write tools for absolute paths in main even when session cwd is a feature worktree");

branch = "feature";
const featureEdit = await handlers.get("tool_call")({
  toolName: "write",
  input: { path: "file", content: "ok" },
}, { cwd: "/repo" });
assert.equal(featureEdit, undefined, "allows edit/write tools off main");

console.log("pi-managed-hooks checks complete");
NODE

PI_HOOK_TEST_WORKTREE="$TMPROOT/worktree" "${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/managed-hooks.mjs"
