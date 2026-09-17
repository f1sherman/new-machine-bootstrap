#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
extension="$repo_root/roles/common/files/pi/extensions/managed-hooks.ts"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
cp "$extension" "$tmp_root/managed-hooks.mjs"

cat > "$tmp_root/check.mjs" <<'NODE'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const [extensionPath, stateRepo] = process.argv.slice(2);
const handlers = new Map();
const ok = (stdout = "") => ({ stdout, stderr: "", code: 0, killed: false });
const pi = {
  on(event, handler) { handlers.set(event, handler); },
  registerTool() {},
  async exec(command, args) {
    if (command === "agent-state-path") return ok();
    if (command === "git" && args.includes("--show-toplevel")) return ok(`${stateRepo}\n`);
    if (command === "git" && args.includes("--show-current")) return ok("main\n");
    return { stdout: "", stderr: "", code: 1, killed: false };
  },
};
const ctx = {
  cwd: stateRepo,
  ui: { setStatus() {}, setFooter() {}, notify() {} },
  sessionManager: { getSessionName: () => "state maintenance" },
};

const { default: install } = await import(pathToFileURL(extensionPath));
install(pi);

const reminder = await handlers.get("before_agent_start")({
  prompt: "run z-fix now",
  systemPromptOptions: { cwd: stateRepo },
}, ctx);
assert.equal(reminder, undefined, "does not recommend repo-start for generated state");

const branchBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git branch feature" },
}, ctx);
assert.equal(branchBlock?.block, true, "still blocks branch creation for generated state");
assert.match(branchBlock.reason, /edit generated agent state in place/i,
  "explains in-place generated-state maintenance");

console.log("pi generated-state managed hook checks complete");
NODE

HOME="$tmp_root/home" AGENT_STATE_PATH_CMD=agent-state-path \
  node "$tmp_root/check.mjs" "$tmp_root/managed-hooks.mjs" \
    "$tmp_root/home/.codex/memories"
