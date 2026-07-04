#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
EXTENSION="$REPO_ROOT/roles/common/files/pi/extensions/spec-shortcut.ts"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

cp "$EXTENSION" "$TMPROOT/spec-shortcut.mjs"

node_cmd=(node)
if ! command -v node >/dev/null 2>&1; then
  mise_bin="${MISE_BIN:-$HOME/.local/bin/mise}"
  node_version="$(yq -r '.tool_versions.runtimes.node' "$REPO_ROOT/vars/tool_versions.yml")"
  node_cmd=("$mise_bin" exec "node@$node_version" -- node)
fi

cat >"$TMPROOT/check.mjs" <<'NODE'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const extensionPath = process.argv[2];
const { default: install } = await import(pathToFileURL(extensionPath));

let registeredShortcut;
let registeredOptions;

const pi = {
  registerShortcut(shortcut, options) {
    registeredShortcut = shortcut;
    registeredOptions = options;
  },
  async exec() {
    throw new Error("spawn ENOENT");
  },
};

const notifications = [];
const ctx = {
  ui: {
    notify(message, level) {
      notifications.push({ message, level });
    },
  },
};

install(pi);
assert.equal(registeredShortcut, "alt+s", "registers alt+s shortcut");
assert.equal(typeof registeredOptions.handler, "function", "registers shortcut handler");

process.env.TMUX = "1";
process.env.TMUX_PANE = "%1";
await registeredOptions.handler(ctx);

assert.equal(notifications.length, 1, "notifies when tmux-spec-open execution throws");
assert.equal(notifications[0].level, "error", "thrown exec errors notify as errors");
assert.match(notifications[0].message, /Could not open spec pane: spawn ENOENT/, "notification includes thrown exec error");

console.log("pi-spec-shortcut checks complete");
NODE

"${node_cmd[@]}" "$TMPROOT/check.mjs" "$TMPROOT/spec-shortcut.mjs"
