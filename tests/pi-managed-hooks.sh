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
const sessionNames = [];
let branch = "main";
let currentSessionName = "";
let windowLabel = "pi main-repo";

const ok = (stdout = "") => ({ stdout, stderr: "", code: 0, killed: false });
const fail = () => ({ stdout: "", stderr: "", code: 1, killed: false });

const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
  setSessionName(name) {
    currentSessionName = name;
    sessionNames.push(name);
  },
  async exec(command, args) {
    calls.push({ command, args });
    if (command === "tmux-agent-state") return ok();
    if (command === "tmux-update-pane-label") return ok();
    if (command === "tmux-window-label") return ok();
    if (command === "tmux" && args[0] === "show-options" && args.at(-1) === "@window-label") return ok(`${windowLabel}\n`);
    if (command === "tmux" && args[0] === "set-option") return ok();
    if (command === "tmux") return fail();
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

const ctx = {
  cwd: "/repo",
  sessionManager: {
    getSessionName() {
      return currentSessionName;
    },
  },
};

install(pi);
assert.equal(typeof handlers.get("session_start"), "function", "registers session_start hook");
assert.equal(typeof handlers.get("before_agent_start"), "function", "registers before_agent_start hook");
assert.equal(typeof handlers.get("tool_call"), "function", "registers tool_call hook");
assert.equal(typeof handlers.get("tool_result"), "function", "registers tool_result hook");

process.env.TMUX = "1";
process.env.TMUX_PANE = "%1";
delete process.env.TMUX_AGENT_STATE_DIR;

await handlers.get("session_start")({}, ctx);
assert.deepEqual(calls.slice(-4), [
  { command: "tmux-update-pane-label", args: ["%1"] },
  { command: "tmux-window-label", args: ["%1"] },
  { command: "tmux-agent-state", args: ["set-kind", "pi"] },
  { command: "tmux", args: ["show-options", "-qv", "-p", "-t", "%1", "@window-label"] },
], "session_start refreshes pane labels before rendering pi window label and naming the session");
assert.deepEqual(sessionNames, ["pi main-repo"], "session_start names the Pi session from tmux @window-label");
assert.equal(typeof handlers.get("tool_result"), "function", "registers tool_result hook");

windowLabel = "pi feature-work";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.deepEqual(sessionNames, ["pi main-repo", "pi feature-work"], "successful bash results resync managed Pi session names from tmux");

currentSessionName = "manual investigation name";
windowLabel = "pi later-worktree";
await handlers.get("tool_result")({ toolName: "bash", isError: false }, ctx);
assert.equal(currentSessionName, "manual investigation name", "manual Pi session names are not overwritten by managed tmux sync");
assert.deepEqual(sessionNames, ["pi main-repo", "pi feature-work"], "manual-name preservation does not call setSessionName again");

await handlers.get("tool_result")({ toolName: "read", isError: false }, ctx);
assert.deepEqual(sessionNames, ["pi main-repo", "pi feature-work"], "non-bash tool results do not resync session names");

await handlers.get("tool_result")({ toolName: "bash", isError: true }, ctx);
assert.deepEqual(sessionNames, ["pi main-repo", "pi feature-work"], "failed bash results do not resync session names");

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

const commitBlock = await handlers.get("tool_call")({
  toolName: "bash",
  input: { command: "git commit -m test" },
}, { cwd: "/repo" });
assert.equal(commitBlock.block, true, "blocks raw git commit");
assert.match(commitBlock.reason, /_commit/, "commit block points to _commit skill");

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
assert.deepEqual(calls.at(-1), {
  command: "tmux",
  args: ["set-option", "-p", "-t", "%1", "@agent_current_spec_path", bashSpecPath],
}, "tracks successful bash-created superpowers spec paths in tmux pane state");

console.log("pi-managed-hooks checks complete");
NODE

PI_HOOK_TEST_WORKTREE="$TMPROOT/worktree" "${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/managed-hooks.mjs"
