import path from "node:path";

const SHORTCUT = "alt+s";
const COMMAND_TIMEOUT_MS = 5000;

function tmuxAvailable() {
  return Boolean(process.env.TMUX && process.env.TMUX_PANE);
}

function specOpenCommand() {
  return path.join(process.env.HOME || "", ".local/bin/tmux-spec-open");
}

function resultMessage(result) {
  return (result.stderr || result.stdout || `exited with code ${result.code}`).trim();
}

export default function specShortcut(pi) {
  pi.registerShortcut(SHORTCUT, {
    description: "Open the current Superpowers spec pane",
    handler: async (ctx) => {
      if (!tmuxAvailable()) {
        ctx.ui.notify("M-s spec shortcut is only available inside tmux.", "warning");
        return;
      }

      const result = await pi.exec(specOpenCommand(), [], { timeout: COMMAND_TIMEOUT_MS });
      if (result.code !== 0) {
        ctx.ui.notify(`Could not open spec pane: ${resultMessage(result)}`, "error");
      }
    },
  });
}
