import fs from "node:fs";
import path from "node:path";

const COMMAND_TIMEOUT_MS = 5000;
const REPO_START_TRIGGERS = /(^|\s)(?:_fix|_spec-first|_spec-to-pr|superpowers:systematic-debugging|superpowers:brainstorming)(?=\s|$)/i;
const SUBJECT_TRIGGERS = /(^|\s)superpowers:(?:brainstorming|systematic-debugging)(?=\s|$)/i;
const SHELL_TOKEN = "[^\\s;&|()]+";
const GIT_PREAMBLE = "(^|[;&|()])\\s*(?:(?:(?:if|then|do|elif|while|until)\\s+|!\\s+)*)((?:(?:[A-Za-z_][A-Za-z0-9_]*)=\\S+\\s+|command\\s+|env\\s+)*)git(?:\\s+-\\S+(?:\\s+\\S+)*)*\\s+";

function warn(message, error) {
  const detail = error instanceof Error ? error.message : String(error ?? "unknown error");
  console.warn(`[managed-hooks] ${message}: ${detail}`);
}

async function exec(pi, command, args, options = {}) {
  try {
    return await pi.exec(command, args, { timeout: COMMAND_TIMEOUT_MS, ...options });
  } catch (error) {
    warn(`${command} ${args.join(" ")} failed`, error);
    return { stdout: "", stderr: String(error), code: 1, killed: false };
  }
}

function inTmux() {
  return Boolean(process.env.TMUX && process.env.TMUX_PANE);
}

function stateFile(key) {
  if (!process.env.TMUX_AGENT_STATE_DIR || !process.env.TMUX_PANE) return undefined;
  return path.join(process.env.TMUX_AGENT_STATE_DIR, `${process.env.TMUX_PANE}.${key}`);
}

function readState(key) {
  const file = stateFile(key);
  if (!file || !fs.existsSync(file)) return "";
  return fs.readFileSync(file, "utf8").trim();
}

async function tmuxOption(pi, key) {
  if (!inTmux()) return "";
  const result = await exec(pi, "tmux", ["show-options", "-qv", "-p", "-t", process.env.TMUX_PANE, key]);
  return result.code === 0 ? result.stdout.trim() : "";
}

async function boundWorktreePath(pi, fallbackCwd) {
  const statePath = readState("@agent_worktree_path");
  if (statePath) return statePath;
  const tmuxPath = await tmuxOption(pi, "@agent_worktree_path");
  return tmuxPath || fallbackCwd;
}

function expandHome(filePath) {
  if (filePath === "~") return process.env.HOME || filePath;
  if (filePath.startsWith("~/")) return path.join(process.env.HOME || "", filePath.slice(2));
  return filePath;
}

function probeDir(filePath, fallbackCwd) {
  const expandedPath = expandHome(filePath);
  let probe = path.isAbsolute(expandedPath) ? expandedPath : path.resolve(fallbackCwd, expandedPath);
  if (!fs.existsSync(probe) || !fs.statSync(probe).isDirectory()) {
    probe = path.dirname(probe);
  }

  while (!fs.existsSync(probe) && probe !== path.dirname(probe)) {
    probe = path.dirname(probe);
  }

  return fs.existsSync(probe) ? probe : fallbackCwd;
}

async function gitRoot(pi, cwd) {
  const result = await exec(pi, "git", ["-C", cwd, "rev-parse", "--show-toplevel"]);
  if (result.code !== 0) return "";
  return result.stdout.trim();
}

async function branchName(pi, cwd) {
  const root = await gitRoot(pi, cwd);
  if (!root) return "";
  const result = await exec(pi, "git", ["-C", root, "branch", "--show-current"]);
  if (result.code !== 0) return "";
  return result.stdout.trim();
}

async function onMainBranch(pi, cwd) {
  return (await branchName(pi, cwd)) === "main";
}

function worktreeCommandBlockReason(command) {
  const normalized = command.replace(/\s+/g, " ").trim();
  if (new RegExp(`${GIT_PREAMBLE}worktree\\s+add(?:\\s|$)`).test(normalized)) {
    return "Do not run git worktree add directly. Use repo-start instead.";
  }
  if (new RegExp(`${GIT_PREAMBLE}worktree\\s+remove(?:\\s|$)`).test(normalized)) {
    return "Do not run git worktree remove directly. Use repo-end to finish work.";
  }

  const checkoutCreate = new RegExp(`${GIT_PREAMBLE}checkout(?:\\s+${SHELL_TOKEN})*\\s+(?:-[^-\\s;&|()]*[bBt][^\\s;&|()]*|--orphan|--track)(?:[=\\s]|$)`);
  const switchCreate = new RegExp(`${GIT_PREAMBLE}switch(?:\\s+${SHELL_TOKEN})*\\s+(?:-[^-\\s;&|()]*[cCt][^\\s;&|()]*|--create|--force-create|--track|--orphan)(?:[=\\s]|$)`);
  const branchListMode = new RegExp(`${GIT_PREAMBLE}branch(?:\\s+${SHELL_TOKEN})*\\s+(?:-l|--list|--contains|--no-contains|--merged|--no-merged|--points-at|--show-current)(?:[=\\s]|$)`);
  const branchCreate = new RegExp(`${GIT_PREAMBLE}branch(?:\\s+(?:-[qvV]+|--quiet|--verbose|--no-color|--no-column|--format(?:=${SHELL_TOKEN})?|--sort(?:=${SHELL_TOKEN})?|--color(?:=${SHELL_TOKEN})?|--column(?:=${SHELL_TOKEN})?|--format\\s+${SHELL_TOKEN}|--sort\\s+${SHELL_TOKEN}|--color\\s+${SHELL_TOKEN}|--column\\s+${SHELL_TOKEN}))*\\s+(?:--\\s+)?[^-\\s;&|()][^\\s;&|()]*`);
  const branchOptionCreate = new RegExp(`${GIT_PREAMBLE}branch(?:\\s+${SHELL_TOKEN})*\\s+(?:-[^-\\s;&|()]*[fcmCM][^\\s;&|()]*|--force|--copy|--move|--track|--no-track|--set-upstream|--create-reflog|--recurse-submodules)(?:[=\\s]|$)`);

  if (checkoutCreate.test(normalized) || switchCreate.test(normalized)) {
    return "Do not create branches directly. Use repo-start <branch> instead.";
  }
  if (!branchListMode.test(normalized) && (branchCreate.test(normalized) || branchOptionCreate.test(normalized))) {
    return "Do not create branches directly. Use repo-start <branch> instead.";
  }
  return "";
}

async function needsSubjectReminder(pi) {
  if (!inTmux()) return false;
  const subject = readState("@agent_subject") || await tmuxOption(pi, "@agent_subject");
  const stale = readState("@agent_subject_stale") || await tmuxOption(pi, "@agent_subject_stale");
  return !subject || Boolean(stale);
}

export default function managedHooks(pi) {
  pi.on("session_start", async () => {
    if (!inTmux()) return;
    await exec(pi, "tmux-agent-state", ["set-kind", "pi"]);
  });

  pi.on("before_agent_start", async (event, ctx) => {
    const notes = [];
    const cwd = await boundWorktreePath(pi, event.systemPromptOptions.cwd || ctx.cwd);

    if (REPO_START_TRIGGERS.test(event.prompt) && await onMainBranch(pi, cwd)) {
      notes.push("You are on main. Before changing files, run `repo-start <branch>` and continue from the created worktree.");
    }

    if (SUBJECT_TRIGGERS.test(event.prompt) && await needsSubjectReminder(pi)) {
      notes.push("Set the tmux agent subject before continuing: `tmux-agent-subject set \"<short subject>\"`.");
    }

    if (notes.length === 0) return;
    return {
      message: {
        customType: "managed-hooks-reminder",
        content: notes.join("\n\n"),
        display: true,
      },
    };
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "bash") {
      const reason = worktreeCommandBlockReason(event.input.command || "");
      if (reason) return { block: true, reason };
      return;
    }

    if (event.toolName === "edit" || event.toolName === "write") {
      const targetPath = event.input.path || event.input.file_path || "";
      const cwd = targetPath ? probeDir(targetPath, ctx.cwd) : ctx.cwd;
      if (await onMainBranch(pi, cwd)) {
        return {
          block: true,
          reason: "File edit blocked on main. Start a non-main branch with repo-start <branch>, then retry.",
        };
      }
    }
  });
}
