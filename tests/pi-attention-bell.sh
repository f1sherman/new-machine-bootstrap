#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
EXTENSION="$REPO_ROOT/roles/common/files/pi/extensions/pi-attention-bell.ts"
TASKS="$REPO_ROOT/roles/common/tasks/main.yml"

if [ ! -f "$EXTENSION" ]; then
  echo "missing extension: $EXTENSION" >&2
  exit 1
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

cp "$EXTENSION" "$TMPROOT/pi-attention-bell.mjs"

node_cmd=(node)
if ! command -v node >/dev/null 2>&1; then
  mise_bin="${MISE_BIN:-$HOME/.local/bin/mise}"
  node_version="$(yq -r '.tool_versions.runtimes.node' "$REPO_ROOT/vars/tool_versions.yml")"
  node_cmd=("$mise_bin" exec "node@$node_version" -- node)
fi

if ! grep -F 'src: pi/extensions/pi-attention-bell.ts' "$TASKS" >/dev/null; then
  echo "main.yml does not install pi-attention-bell.ts" >&2
  exit 1
fi

if grep -E 'osascript|display notification|terminal-notifier|notify-send|zenity|OSC 9|OSC 777|]9;|]777;' "$EXTENSION" >/dev/null; then
  echo "extension must not use desktop notifications or OSC notification sequences" >&2
  exit 1
fi

cat >"$TMPROOT/check.mjs" <<'NODE'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const { default: install } = await import(pathToFileURL(extensionPath));

const handlers = new Map();
const pi = {
  on(event, handler) {
    handlers.set(event, handler);
  },
};

let captured = "";
const originalWrite = process.stdout.write;
const originalIsTTY = Object.getOwnPropertyDescriptor(process.stdout, "isTTY");
process.stdout.write = (chunk, encoding, callback) => {
  captured += String(chunk);
  if (typeof encoding === "function") encoding();
  if (typeof callback === "function") callback();
  return true;
};

try {
  install(pi);

  assert.equal(typeof handlers.get("agent_end"), "function", "registers agent_end handler");
  assert.equal(typeof handlers.get("session_start"), "function", "registers session_start handler");

  Object.defineProperty(process.stdout, "isTTY", { configurable: true, value: true });
  await handlers.get("agent_end")({}, {});
  assert.equal(captured, "\x07", "agent_end emits one BEL when stdout is a TTY");

  Object.defineProperty(process.stdout, "isTTY", { configurable: true, value: false });
  captured = "";
  await handlers.get("agent_end")({}, {});
  assert.equal(captured, "", "agent_end skips BEL when stdout is not a TTY");

  Object.defineProperty(process.stdout, "isTTY", { configurable: true, value: true });

  captured = "";
  const calls = [];
  const ui = {
    async select(...args) { calls.push(["select", this, args]); return "choice"; },
    async confirm(...args) { calls.push(["confirm", this, args]); return true; },
    async input(...args) { calls.push(["input", this, args]); return "value"; },
    async editor(...args) { calls.push(["editor", this, args]); return "edited"; },
    async custom(...args) { calls.push(["custom", this, args]); return "custom"; },
    notify() { throw new Error("notify should not be wrapped"); },
  };
  const ctx = { ui };

  await handlers.get("session_start")({}, ctx);
  await handlers.get("session_start")({}, ctx);

  assert.equal(await ui.select("Pick", ["A"]), "choice");
  assert.equal(await ui.confirm("Confirm", "Message"), true);
  assert.equal(await ui.input("Input", "hint text"), "value");
  assert.equal(await ui.editor("Editor", "prefill"), "edited");
  assert.equal(await ui.custom(() => ({})), "custom");

  assert.equal(captured, "\x07\x07\x07\x07\x07", "each blocking UI method emits one BEL after idempotent wrapping");
  assert.deepEqual(calls.map((call) => call[0]), ["select", "confirm", "input", "editor", "custom"]);
  assert.ok(calls.every((call) => call[1] === ui), "wrappers preserve original this binding");

  captured = "";
  const badCtx = { ui: null };
  await handlers.get("session_start")({}, badCtx);
  assert.equal(captured, "", "bad UI context fails open without BEL spam");
} finally {
  process.stdout.write = originalWrite;
  if (originalIsTTY) {
    Object.defineProperty(process.stdout, "isTTY", originalIsTTY);
  } else {
    delete process.stdout.isTTY;
  }
}

console.log("pi-attention-bell checks complete");
NODE

"${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/pi-attention-bell.mjs"
