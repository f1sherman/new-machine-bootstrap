#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
EXTENSION="$REPO_ROOT/roles/common/files/pi/extensions/pi-attention-bell.ts"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

export PI_SKIP_VERSION_CHECK=1
export HOME="$TMPROOT/home"
mkdir -p "$HOME" "$TMPROOT/project"

cat >"$TMPROOT/prompt-extension.ts" <<'TS'
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function promptExtension(pi: ExtensionAPI) {
  pi.registerCommand("attention-bell-confirm", {
    description: "Open a confirmation prompt for attention-bell E2E testing",
    handler: async (_args, ctx) => {
      await ctx.ui.confirm("Attention bell E2E", "Confirm prompt bell?");
    },
  });
}
TS

cat >"$TMPROOT/agent-end-provider.ts" <<'TS'
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function agentEndProvider(pi: ExtensionAPI) {
  pi.registerProvider("attention-bell-e2e", {
    baseUrl: "http://127.0.0.1:9/v1",
    apiKey: "test-key",
    api: "openai-completions",
    models: [
      {
        id: "attention-bell-e2e-model",
        name: "Attention Bell E2E Model",
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 8192,
        maxTokens: 128,
      },
    ],
    streamSimple: async function* () {
      yield { type: "text_delta", delta: "done" };
    },
  });
}
TS

run_with_tty() {
  local outfile="$1"
  shift
  script -q -f -c "$*" "$outfile" >/dev/null 2>&1 || return "$?"
}

assert_bel() {
  local file="$1" label="$2"
  if ! ruby -e 'exit(File.binread(ARGV.fetch(0)).include?("\a") ? 0 : 1)' "$file"; then
    echo "missing BEL for $label" >&2
    ruby -e 'p File.binread(ARGV.fetch(0))[0,1000]' "$file" >&2 || true
    exit 1
  fi
}

agent_end_log="$TMPROOT/agent-end.log"
run_with_tty "$agent_end_log" "cd '$TMPROOT/project' && timeout 15s pi --print --no-session --no-tools --no-context-files --no-skills --no-prompt-templates --extension '$EXTENSION' --extension '$TMPROOT/agent-end-provider.ts' --model attention-bell-e2e/attention-bell-e2e-model 'say done'"
assert_bel "$agent_end_log" "agent_end"

prompt_log="$TMPROOT/prompt.log"
run_with_tty "$prompt_log" "cd '$TMPROOT/project' && printf '/attention-bell-confirm\n' | timeout 15s pi --no-session --no-context-files --no-skills --no-prompt-templates --extension '$EXTENSION' --extension '$TMPROOT/prompt-extension.ts'"
assert_bel "$prompt_log" "extension prompt"

echo "pi-attention-bell E2E checks complete"
