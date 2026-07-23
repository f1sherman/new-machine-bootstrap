import fs from "node:fs";
import path from "node:path";

const COMMAND_TIMEOUT_MS = 5000;
const SUBJECT_CHILD_TIMEOUT_MS = 15000;
const CODEX_MANAGED_CHILD_MODEL = "openai-codex/gpt-5.4-mini";
const OPENAI_MANAGED_CHILD_MODEL = "openai/gpt-4.1-mini";
const MANAGED_CHILD_MODEL_OVERRIDE = "PI_MANAGED_CHILD_MODEL";
let cachedManagedChildAuthSignature;
let cachedManagedChildModel = OPENAI_MANAGED_CHILD_MODEL;
const SUBJECT_CHILD_SYSTEM_PROMPT = "Return one concise noun phrase describing the user's task. Output only the phrase on one line, with no quotes, prefix, or explanation.";
const SUBJECT_MAX_LENGTH = 512;
const SESSION_GOAL_CHILD_SYSTEM_PROMPT = "Return one concise noun phrase of at most 80 characters describing the new session's broad goal. Output only the phrase on one line, without quotes, a goal: prefix, or explanation.";
const SESSION_GOAL_MAX_LENGTH = 80;
const SESSION_GOAL_ENTRY_TYPE = "session-goal";
const SESSION_GOAL_STATUS_KEY = "session-goal";
const SESSION_GOAL_PLACEHOLDER = "determining…";
const MANAGED_PI_SESSION_NAME_OPTION = "@pi_managed_session_name";
const REPO_START_TRIGGERS = /(^|\s)(?:z-fix|z-spec-first|z-quick-pr|superpowers:systematic-debugging|superpowers:brainstorming)(?=\s|$)/i;
const SHELL_TOKEN = "[^\\s;&|()]+";
const GIT_PREAMBLE = "(^|[;&|()])\\s*(?:(?:(?:if|then|do|elif|while|until)\\s+|!\\s+)*)((?:(?:[A-Za-z_][A-Za-z0-9_]*)=\\S+\\s+|command\\s+|env\\s+|sudo(?:\\s+-\\S+)*\\s+|time(?:\\s+-\\S+)*\\s+)*)git(?:\\s+-\\S+(?:\\s+\\S+)*)*\\s+";

function warn(message, error) {
  const detail = error instanceof Error ? error.message : String(error ?? "unknown error");
  console.warn(`[managed-hooks] ${message}: ${detail}`);
}

function managedChildAuthPath() {
  const codingAgentDir = process.env.PI_CODING_AGENT_DIR?.trim();
  if (codingAgentDir) return path.join(expandHome(codingAgentDir), "auth.json");
  return path.join(process.env.HOME || "", ".pi", "agent", "auth.json");
}

function managedChildAuthSignature(authPath) {
  try {
    const stat = fs.statSync(authPath);
    return [authPath, stat.dev, stat.ino, stat.size, stat.mtimeMs, stat.ctimeMs].join(":");
  } catch {
    return `${authPath}:missing`;
  }
}

function hasCodexOAuth(auth) {
  const credential = auth?.["openai-codex"];
  return credential?.type === "oauth"
    && typeof credential.access === "string" && credential.access.length > 0
    && typeof credential.refresh === "string" && credential.refresh.length > 0;
}

function managedChildModel() {
  const override = process.env[MANAGED_CHILD_MODEL_OVERRIDE]?.trim();
  if (override) return override;

  const authPath = managedChildAuthPath();
  const signature = managedChildAuthSignature(authPath);
  if (signature === cachedManagedChildAuthSignature) return cachedManagedChildModel;

  cachedManagedChildAuthSignature = signature;
  try {
    const auth = JSON.parse(fs.readFileSync(authPath, "utf8"));
    cachedManagedChildModel = hasCodexOAuth(auth)
      ? CODEX_MANAGED_CHILD_MODEL
      : OPENAI_MANAGED_CHILD_MODEL;
  } catch {
    cachedManagedChildModel = OPENAI_MANAGED_CHILD_MODEL;
  }
  return cachedManagedChildModel;
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

function ownsTmuxPane() {
  return inTmux() && Boolean(process.stdout.isTTY);
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

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function piSessionNameFromTmuxLabel(label, cwd) {
  let sessionName = label.trim().replace(/^pi(?:\s*:\s*|\s+)/i, "").trim();
  const directoryName = cwd ? path.basename(cwd) : "";
  if (directoryName) {
    sessionName = sessionName
      .replace(new RegExp(`^${escapeRegExp(directoryName)}(?:\\s*:\\s*|\\s+|$)`), "")
      .trim();
  }
  return sessionName;
}

let lastManagedSessionName = "";
let currentSessionGoal = "";

async function refreshTmuxLabels(pi) {
  if (!inTmux()) return;
  await exec(pi, "tmux-update-pane-label", [process.env.TMUX_PANE]);
  await exec(pi, "tmux-window-label", [process.env.TMUX_PANE]);
}

async function managedWrite(pi, command, args, failureMessage) {
  let result;
  try {
    result = await pi.exec(command, args, { timeout: COMMAND_TIMEOUT_MS });
  } catch (error) {
    console.warn(failureMessage, {
      name: error instanceof Error ? error.name || "Error" : "Error",
      code: error?.code,
      exitCode: error?.exitCode,
      killed: error?.killed,
    });
    return false;
  }
  if (result.code !== 0 || result.killed) {
    console.warn(failureMessage, { code: result.code, killed: result.killed });
    return false;
  }
  return true;
}

async function setManagedPiSessionName(pi, ctx, sessionName, maySet = () => true) {
  if (!sessionName || typeof pi.setSessionName !== "function") return false;
  let currentName = ctx?.sessionManager?.getSessionName?.() || "";
  if (currentName) {
    const marker = await tmuxOption(pi, MANAGED_PI_SESSION_NAME_OPTION);
    currentName = ctx?.sessionManager?.getSessionName?.() || "";
    if (marker === currentName) lastManagedSessionName = currentName;
  }
  if (currentName === sessionName) return !inTmux() || currentName === lastManagedSessionName;
  if (currentName && currentName !== lastManagedSessionName) return false;
  if (!maySet()) return false;

  if (inTmux()) {
    const marked = await managedWrite(pi, "tmux", [
      "set-option", "-p", "-t", process.env.TMUX_PANE,
      MANAGED_PI_SESSION_NAME_OPTION, sessionName,
    ], "[managed-hooks] tmux managed-name marker write failed");
    if (!marked || !maySet()) return false;
  }
  lastManagedSessionName = sessionName;
  pi.setSessionName(sessionName);
  return true;
}

async function syncSessionNameFromTmux(pi, ctx) {
  if (!inTmux() || currentSessionGoal) return;

  const namingStatus = await canonicalSessionNameStatus(pi);
  if (namingStatus.kind === "unavailable") return;
  if (namingStatus.state === "provisional" && namingStatus.source === "agent") return;

  const label = await tmuxOption(pi, "@window-label");
  if (!label) return;

  const labelPath = await boundWorktreePath(pi, ctx?.cwd || "");
  const sessionName = piSessionNameFromTmuxLabel(label, labelPath);
  if (!sessionName) return;

  try {
    await setManagedPiSessionName(pi, ctx, sessionName, () => !currentSessionGoal);
  } catch (error) {
    warn("set Pi session name from tmux label failed", error);
  }
}

async function publishTmuxIdentity(pi, source, subject) {
  if (!ownsTmuxPane()) return false;
  return managedWrite(
    pi,
    "tmux-agent-state",
    ["set-identity", source, subject],
    "[managed-hooks] tmux identity write failed",
  );
}

async function applyTmuxSubject(pi, subject) {
  const result = await exec(pi, "tmux-agent-subject", ["set", subject]);
  if (result.code !== 0 || result.killed) {
    console.warn("[managed-hooks] tmux-agent-subject set failed", {
      code: result.code,
      killed: result.killed,
    });
    return false;
  }
  return true;
}

async function syncTmuxSubjectFromSession(pi, ctx) {
  if (!ownsTmuxPane()) return;
  const sessionFile = ctx?.sessionManager?.getSessionFile?.() || "";
  const sessionName = ctx?.sessionManager?.getSessionName?.()?.trim() || "";
  if (!sessionFile || !sessionName) return;

  const boundSessionFile = await tmuxOption(pi, "@persist_pi_session_file");
  if (!boundSessionFile || boundSessionFile === sessionFile) return;

  await applyTmuxSubject(pi, sessionName);
}

async function bindPaneSessionFile(pi, ctx) {
  // Nested / non-interactive pi invocations (subagent children, `pi -p`)
  // inherit TMUX_PANE but run without a TTY; they must not clobber the
  // pane's session binding used by `pir`.
  if (!ownsTmuxPane()) return;
  const sessionFile = ctx?.sessionManager?.getSessionFile?.() || "";
  if (!sessionFile) return;
  await exec(pi, "tmux", ["set-option", "-p", "-t", process.env.TMUX_PANE, "@persist_pi_session_file", sessionFile]);
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

function shellWrappedPayload(segment) {
  const match = segment.match(/^(?:command\s+|env\s+(?:\S+\s+)*|sudo(?:\s+-\S+)*\s+|time(?:\s+-\S+)*\s+)*(?:\S+\/)?(?:bash|sh|zsh)(?:\s+-\S+)*\s+-[A-Za-z]*c[A-Za-z]*(?:\s+\S+)*\s+(['"])([\s\S]*)\1(?:\s+.*)?$/);
  return match ? match[2] : "";
}

function splitShellSegments(command) {
  const segments = [];
  let current = "";
  let quote = "";
  let escaped = false;

  for (let i = 0; i < command.length; i += 1) {
    const char = command[i];
    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }
    if (char === "\\" && quote !== "'") {
      current += char;
      escaped = true;
      continue;
    }
    if (quote) {
      current += char;
      if (char === quote) quote = "";
      continue;
    }
    if (char === "'" || char === '"') {
      current += char;
      quote = char;
      continue;
    }
    if (char === "&" || char === "|") {
      if (current.trim()) segments.push(current.trim());
      current = "";
      if (command[i + 1] === char) i += 1;
      continue;
    }
    if (char === ";" || char === "(" || char === ")" || char === "\n" || char === "\r") {
      if (current.trim()) segments.push(current.trim());
      current = "";
      continue;
    }
    current += char;
  }

  if (current.trim()) segments.push(current.trim());
  return segments;
}

function splitCommandSegments(command) {
  const expanded = [];
  for (const segment of splitShellSegments(command)) {
    const payload = shellWrappedPayload(segment);
    if (payload) {
      expanded.push(...splitCommandSegments(payload));
    } else {
      expanded.push(segment);
    }
  }
  return expanded;
}

function unquoteShellToken(token) {
  if ((token.startsWith('"') && token.endsWith('"')) || (token.startsWith("'") && token.endsWith("'"))) {
    return token.slice(1, -1);
  }
  return token;
}

function gitCommandCwd(segment, fallbackCwd) {
  const tokens = segment.replace(/\s+/g, " ").trim().split(" ").map(unquoteShellToken);
  const gitIndex = tokens.indexOf("git");
  if (gitIndex === -1) return fallbackCwd;

  let selectedCwd = fallbackCwd;
  for (let i = gitIndex + 1; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === "push" || token === "commit" || token === "add" || token === "worktree" || token === "branch" || token === "switch" || token === "checkout") break;
    if (token === "-C" && tokens[i + 1]) {
      selectedCwd = path.isAbsolute(tokens[i + 1]) ? tokens[i + 1] : path.resolve(selectedCwd, tokens[i + 1]);
      i += 1;
    } else if (token.startsWith("-C") && token.length > 2) {
      const value = token.slice(2);
      selectedCwd = path.isAbsolute(value) ? value : path.resolve(selectedCwd, value);
    }
  }

  return selectedCwd;
}

function rawCommitBlockReason(command) {
  for (const segment of splitCommandSegments(command)) {
    const normalized = segment.replace(/\s+/g, " ").trim();
    if (new RegExp(`${GIT_PREAMBLE}commit([\\s;&|()]|$)`).test(normalized)) {
      return "Do not run git commit directly. Use the z-commit skill instead.";
    }
  }
  return "";
}

function changedDirectory(segment, cwd) {
  const match = segment.replace(/\s+/g, " ").trim().match(/^cd(?:\s+--)?\s+([^\s;&|()]+)$/);
  if (!match) return "";
  const target = expandHome(unquoteShellToken(match[1]));
  return path.isAbsolute(target) ? target : path.resolve(cwd, target);
}

function changedDirectoryCandidates(segment, cwd) {
  const nextCwd = changedDirectory(segment, cwd);
  if (!nextCwd) return [];
  return [cwd, nextCwd];
}

async function anyMainBranch(pi, cwds) {
  for (const cwd of cwds) {
    if (await onMainBranch(pi, cwd)) return true;
  }
  return false;
}

function gitPushPositionals(segment) {
  const tokens = segment.replace(/\s+/g, " ").trim().split(" ").map(unquoteShellToken);
  const pushIndex = tokens.indexOf("push");
  if (pushIndex === -1) return [];

  const positionals = [];
  for (let i = pushIndex + 1; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === "--") {
      positionals.push(...tokens.slice(i + 1));
      break;
    }
    if (token === "-o" || token === "--push-option" || token === "--receive-pack" || token === "--exec" || token === "--repo") {
      i += 1;
      continue;
    }
    if (token.startsWith("-")) continue;
    positionals.push(token);
  }
  return positionals;
}

async function pushMainBlockReason(pi, command, cwd) {
  const mainRef = "\\+?(([^\\s;&|()]+:)?(main|refs/heads/main)|:(main|refs/heads/main)?|:)";
  let segmentCwds = [cwd];
  for (const segment of splitShellSegments(command)) {
    const payload = shellWrappedPayload(segment);
    if (payload) {
      for (const segmentCwd of segmentCwds) {
        const nestedReason = await pushMainBlockReason(pi, payload, segmentCwd);
        if (nestedReason) return nestedReason;
      }
      continue;
    }

    const normalized = segment.replace(/\s+/g, " ").trim();
    const nextCwds = segmentCwds.flatMap((segmentCwd) => changedDirectoryCandidates(segment, segmentCwd));
    if (nextCwds.length > 0) {
      segmentCwds = [...new Set(nextCwds)];
      continue;
    }

    if (new RegExp(`${GIT_PREAMBLE}push(?:\\s+${SHELL_TOKEN})*\\s+${mainRef}([\\s;&|()]|$)`).test(normalized)) {
      return "Do not push to main directly. Open a PR.";
    }
    if (new RegExp(`${GIT_PREAMBLE}push(?:\\s+${SHELL_TOKEN})*\\s+(--all|--mirror)([\\s;&|()]|$)`).test(normalized)) {
      return "Do not push to main directly. Open a PR.";
    }

    const isGitPush = new RegExp(`${GIT_PREAMBLE}push([\\s;&|()]|$)`).test(normalized);
    if (!isGitPush) continue;

    const selectedCwds = segmentCwds.map((segmentCwd) => gitCommandCwd(segment, segmentCwd));
    const pushPositionals = gitPushPositionals(segment);
    const safePushMode = /(^|\s)(--dry-run|--tags)(\s|$)/.test(normalized);
    const headPush = pushPositionals.includes("HEAD");
    const implicitPush = !safePushMode && pushPositionals.length <= 1;
    if ((headPush || implicitPush) && await anyMainBranch(pi, selectedCwds)) {
      return "Do not push to main directly. Open a PR.";
    }
  }

  return "";
}

function isSuperpowersDocsPath(filePath) {
  return /(^|\/)docs\/superpowers(\/|$)/.test(filePath.replaceAll(path.sep, "/"));
}

function forceAddOperandsTargetSuperpowersDocs(segment, cwd) {
  const tokens = segment.replace(/\s+/g, " ").trim().split(" ").map(unquoteShellToken);
  const addIndex = tokens.indexOf("add");
  if (addIndex === -1) return false;
  for (const token of tokens.slice(addIndex + 1)) {
    if (!token || token.startsWith("-")) continue;
    const expanded = expandHome(token);
    const absolute = path.isAbsolute(expanded) ? expanded : path.resolve(cwd, expanded);
    if (isSuperpowersDocsPath(absolute)) return true;
  }
  return false;
}

function forceAddSuperpowersDocsBlockReason(command, cwd) {
  let segmentCwd = cwd;
  for (const segment of splitCommandSegments(command)) {
    const normalized = segment.replace(/\s+/g, " ").trim();
    const nextCwd = changedDirectory(segment, segmentCwd);
    if (nextCwd) {
      segmentCwd = nextCwd;
      continue;
    }

    const isGitAdd = new RegExp(`${GIT_PREAMBLE}add([\\s;&|()]|$)`).test(normalized);
    const hasForce = /(^|\s)--f[a-z]*(\s|=|$)|(^|\s)-[A-Za-z]*f[A-Za-z]*(\s|$)/.test(normalized);
    const gitCwd = gitCommandCwd(segment, segmentCwd);
    if (isGitAdd && hasForce && (normalized.includes("docs/superpowers") || isSuperpowersDocsPath(gitCwd) || forceAddOperandsTargetSuperpowersDocs(segment, gitCwd))) {
      return "docs/superpowers/ may be gitignored intentionally. Do not bypass .gitignore with -f / --force.";
    }
  }
  return "";
}

async function bashCommandBlockReason(pi, command, cwd) {
  return worktreeCommandBlockReason(command)
    || rawCommitBlockReason(command)
    || await pushMainBlockReason(pi, command, cwd)
    || forceAddSuperpowersDocsBlockReason(command, cwd);
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

async function canonicalSessionNameStatus(pi) {
  if (!inTmux()) return { kind: "non-branch" };
  const result = await exec(pi, "tmux-agent-state", ["status"]);
  if (result.code !== 0) return { kind: "unavailable" };

  const output = result.stdout.trim();
  if (!output) return { kind: "non-branch" };
  const fields = output.split("\t");
  const [state, source, subject] = fields;
  if (fields.length !== 3 || !subject || !["provisional", "active", "completed"].includes(state)
    || !["agent", "branch", "goal", "manual"].includes(source)) {
    return { kind: "unavailable" };
  }
  if (state === "active" && source === "branch") return { kind: "branch", subject };
  return { kind: "non-branch", state, source };
}

async function needsSubjectReminder(pi) {
  if (!inTmux()) return false;
  const result = await exec(pi, "tmux-agent-state", ["status"]);
  if (result.code !== 0) return false;
  const currentTask = result.stdout.trim();
  return !currentTask || currentTask.startsWith("completed\t");
}

function normalizeGeneratedSubject(output) {
  const subject = output.trim();
  if (!subject || subject.length > SUBJECT_MAX_LENGTH || subject.includes("\n") || subject.includes("\r")) return "";
  return subject;
}

function subjectChildFailureDetails(value) {
  if (value instanceof Error) {
    return {
      name: value.name || "Error",
      code: value.code,
      exitCode: value.exitCode,
      killed: value.killed,
    };
  }

  return {
    name: "SubjectChildResult",
    code: value?.code,
    exitCode: value?.exitCode,
    killed: value?.killed,
  };
}

async function setSubjectFromSubagent(pi, prompt, cwd, signal) {
  const framedPrompt = `Task: ${prompt}`;
  const model = managedChildModel();
  let result;
  try {
    result = await pi.exec("pi", [
      "--mode", "text",
      "--print",
      "--no-session",
      "--model", model,
      "--thinking", "off",
      "--no-tools",
      "--no-extensions",
      "--no-skills",
      "--no-prompt-templates",
      "--no-themes",
      "--no-context-files",
      "--no-approve",
      "--system-prompt", SUBJECT_CHILD_SYSTEM_PROMPT,
      framedPrompt,
    ], { cwd, timeout: SUBJECT_CHILD_TIMEOUT_MS, signal });
  } catch (error) {
    console.warn("[managed-hooks] tmux subject child failed", subjectChildFailureDetails(error));
    return false;
  }

  if (result.code !== 0 || result.killed) {
    console.warn("[managed-hooks] tmux subject child failed", subjectChildFailureDetails(result));
    return false;
  }

  const subject = normalizeGeneratedSubject(result.stdout);
  if (!subject) {
    warn("tmux subject child returned an invalid subject", "empty, multiline, or over 512 characters");
    return false;
  }

  return applyTmuxSubject(pi, subject);
}

function normalizeSuperpowersSpecPath(candidatePath, cwd, repoRoot, resolveFrom = cwd) {
  if (!candidatePath) return "";
  const unquoted = candidatePath.replace(/^['\"`]+|['\"`.,:;]+$/g, "");
  if (/[*?[\]]/.test(unquoted)) return "";
  const expanded = expandHome(unquoted.startsWith("./") ? unquoted.slice(2) : unquoted);
  const absolute = path.isAbsolute(expanded) ? expanded : path.resolve(resolveFrom, expanded);
  const root = repoRoot || cwd;
  const relative = path.relative(root, absolute).replaceAll(path.sep, "/");
  if (/^docs\/superpowers\/specs\/[^/]+[.]md$/.test(relative)) return absolute;
  return "";
}

function superpowersSpecPath(event, cwd, repoRoot) {
  return normalizeSuperpowersSpecPath(event.input.path || event.input.file_path || "", cwd, repoRoot, cwd);
}

function superpowersSpecPathsInCommand(command, cwd, repoRoot) {
  const paths = [];
  const pathPattern = /(?:^|[\s'"`])((?:\.\/)?docs\/superpowers\/specs\/[^\s'"`;&|()<>]+[.]md|\/[^\s'"`;&|()<>]*\/docs\/superpowers\/specs\/[^\s'"`;&|()<>]+[.]md)(?=$|[\s'"`.,:;]|[;&|()<>])/g;
  for (const match of command.matchAll(pathPattern)) {
    const specPath = normalizeSuperpowersSpecPath(match[1], cwd, repoRoot, repoRoot || cwd);
    if (specPath && fs.existsSync(specPath) && !paths.includes(specPath)) paths.push(specPath);
  }
  return paths;
}

async function setCurrentSpec(pi, specPath) {
  await exec(pi, "tmux", ["set-option", "-p", "-t", process.env.TMUX_PANE, "@agent_current_spec_path", specPath]);
}

async function updateCurrentSpec(pi, event, ctx) {
  if (!inTmux()) return;
  if (event.toolName !== "edit" && event.toolName !== "write") return;
  const targetPath = event.input.path || event.input.file_path || "";
  const targetCwd = targetPath ? probeDir(targetPath, ctx.cwd) : ctx.cwd;
  const root = await gitRoot(pi, targetCwd);
  const specPath = superpowersSpecPath(event, ctx.cwd, root);
  if (!specPath) return;
  await setCurrentSpec(pi, specPath);
}

async function updateCurrentSpecFromBash(pi, event, ctx) {
  if (!inTmux() || event.isError) return;
  const command = event.input?.command || "";
  if (!command.includes("docs/superpowers/specs")) return;
  const cwd = await boundWorktreePath(pi, ctx.cwd);
  const root = await gitRoot(pi, cwd);
  const specPaths = superpowersSpecPathsInCommand(command, cwd, root);
  if (specPaths.length !== 1) return;
  await setCurrentSpec(pi, specPaths[0]);
}

function normalizeSessionGoalSubject(value) {
  if (typeof value !== "string" || value.includes("\n") || value.includes("\r")) return "";
  const subject = value.trim().replace(/ +/g, " ");
  if (!subject || subject.length > SESSION_GOAL_MAX_LENGTH) return "";
  if (/\p{Cc}/u.test(subject) || /^goal\s*:/i.test(subject) || /["'`]/.test(subject)) return "";
  return subject;
}

function storedSessionGoal(entry) {
  if (entry?.type !== "custom" || entry.customType !== SESSION_GOAL_ENTRY_TYPE) return "";
  return normalizeSessionGoalSubject(entry.data?.subject);
}

function restoreSessionGoal(ctx) {
  const entries = ctx?.sessionManager?.getBranch?.() || [];
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const subject = storedSessionGoal(entries[index]);
    if (subject) return subject;
  }
  return "";
}

function renderSessionGoal(ctx) {
  ctx?.ui?.setStatus?.(
    SESSION_GOAL_STATUS_KEY,
    `goal: ${currentSessionGoal || SESSION_GOAL_PLACEHOLDER}`,
  );
}

function sessionGoalFailureDetails(value) {
  return {
    name: value instanceof Error ? value.name || "Error" : "SessionGoalChildResult",
    code: value?.code,
    exitCode: value?.exitCode,
    killed: value?.killed,
  };
}

function recordSessionGoalFailure(value) {
  console.warn("[managed-hooks] session goal child failed", sessionGoalFailureDetails(value));
}

async function evaluateInitialSessionGoal(pi, request, signal) {
  return pi.exec("pi", [
    "--mode", "text",
    "--print",
    "--no-session",
    "--model", managedChildModel(),
    "--thinking", "off",
    "--no-tools",
    "--no-extensions",
    "--no-skills",
    "--no-prompt-templates",
    "--no-themes",
    "--no-context-files",
    "--no-approve",
    "--system-prompt", SESSION_GOAL_CHILD_SYSTEM_PROMPT,
    `New session prompt: ${request.prompt}`,
  ], { cwd: request.cwd, timeout: SUBJECT_CHILD_TIMEOUT_MS, signal });
}

export default function managedHooks(pi) {
  let sessionGoalGeneration = 0;
  let sessionGoalRunning;
  let goalApplicationChain = Promise.resolve();

  function requestIsCurrent(request, ctx) {
    const sessionFile = ctx?.sessionManager?.getSessionFile?.() || "";
    return request.generation === sessionGoalGeneration && request.sessionFile === sessionFile;
  }

  function serializeGoalOperation(operation) {
    const result = goalApplicationChain.then(operation);
    goalApplicationChain = result.catch(() => {});
    return result;
  }

  function applySessionGoal(pi, ctx, subject, options = {}) {
    return serializeGoalOperation(async () => {
      const normalized = normalizeSessionGoalSubject(subject);
      if (!normalized) throw new Error("Session goal must be one line, unquoted, and at most 80 characters.");
      if (options.onlyIfUnset
        && (!requestIsCurrent(options.request, ctx) || currentSessionGoal)) {
        return currentSessionGoal;
      }
      if (normalized === currentSessionGoal) return normalized;

      pi.appendEntry(SESSION_GOAL_ENTRY_TYPE, { subject: normalized });
      currentSessionGoal = normalized;
      renderSessionGoal(ctx);
      const maySet = () => !options.onlyIfUnset
        || (requestIsCurrent(options.request, ctx) && currentSessionGoal === normalized);
      const named = await setManagedPiSessionName(pi, ctx, normalized, maySet);
      if (named && maySet()) await publishTmuxIdentity(pi, "goal", normalized);
      return normalized;
    });
  }

  function startInitialSessionGoalEvaluation(pi, prompt, cwd, ctx) {
    if (currentSessionGoal || sessionGoalRunning?.generation === sessionGoalGeneration) return;

    const request = {
      generation: sessionGoalGeneration,
      sessionFile: ctx?.sessionManager?.getSessionFile?.() || "",
      prompt,
      cwd,
      ctx,
    };
    const running = {
      generation: sessionGoalGeneration,
      controller: new AbortController(),
    };
    sessionGoalRunning = running;

    void (async () => {
      try {
        const result = await evaluateInitialSessionGoal(pi, request, running.controller.signal);
        if (result.code !== 0 || result.killed) {
          if (requestIsCurrent(request, request.ctx)) recordSessionGoalFailure(result);
          return;
        }
        const subject = normalizeSessionGoalSubject(
          typeof result.stdout === "string" ? result.stdout.trimEnd() : result.stdout,
        );
        if (!subject) {
          if (requestIsCurrent(request, request.ctx)) recordSessionGoalFailure(result);
          return;
        }
        await applySessionGoal(pi, request.ctx, subject, { onlyIfUnset: true, request });
      } catch (error) {
        if (requestIsCurrent(request, request.ctx)) recordSessionGoalFailure(error);
      } finally {
        if (sessionGoalRunning === running) sessionGoalRunning = undefined;
      }
    })();
  }

  function resetSessionGoalLifecycle(ctx) {
    sessionGoalGeneration += 1;
    sessionGoalRunning?.controller.abort();
    currentSessionGoal = restoreSessionGoal(ctx);
    renderSessionGoal(ctx);
  }

  async function applyRestoredVisibleIdentity(pi, ctx) {
    const sessionName = ctx?.sessionManager?.getSessionName?.()?.trim() || "";
    const marker = await tmuxOption(pi, MANAGED_PI_SESSION_NAME_OPTION);
    lastManagedSessionName = marker === sessionName ? sessionName : "";
    const manualSessionName = sessionName && sessionName !== lastManagedSessionName;
    if (manualSessionName) {
      await publishTmuxIdentity(pi, "manual", sessionName);
      return true;
    }
    if (!currentSessionGoal) return false;

    const named = await setManagedPiSessionName(pi, ctx, currentSessionGoal);
    if (named) await publishTmuxIdentity(pi, "goal", currentSessionGoal);
    return true;
  }

  pi.registerTool({
    name: "set_session_goal",
    label: "Set Session Goal",
    description: "Set the durable broad goal and automatic identity for the current Pi session",
    parameters: {
      type: "object",
      properties: {
        goal: { type: "string", description: "Concise broad session goal, at most 80 characters" },
      },
      required: ["goal"],
      additionalProperties: false,
    },
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const goal = await applySessionGoal(pi, ctx, params.goal);
      return { content: [{ type: "text", text: `Session goal set to: ${goal}` }], details: { goal } };
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    resetSessionGoalLifecycle(ctx);
    if (!inTmux()) return;
    await syncTmuxSubjectFromSession(pi, ctx);
    await refreshTmuxLabels(pi);
    await exec(pi, "tmux-agent-state", ["set-kind", "pi"]);
    await bindPaneSessionFile(pi, ctx);

    const namingStatus = await canonicalSessionNameStatus(pi);
    const restoredIdentityApplied = await serializeGoalOperation(
      () => applyRestoredVisibleIdentity(pi, ctx),
    );
    if (restoredIdentityApplied) return;
    if (namingStatus.kind === "branch") {
      await setManagedPiSessionName(pi, ctx, namingStatus.subject);
    } else if (namingStatus.kind === "non-branch") {
      await syncSessionNameFromTmux(pi, ctx);
    }
  });

  pi.on("session_info_changed", async (event) => {
    const sessionName = event.name?.trim() || "";
    if (!sessionName || !ownsTmuxPane()) return;
    const marker = await tmuxOption(pi, MANAGED_PI_SESSION_NAME_OPTION);
    const managedGoal = Boolean(currentSessionGoal)
      && sessionName === currentSessionGoal
      && (sessionName === lastManagedSessionName || sessionName === marker);
    await publishTmuxIdentity(pi, managedGoal ? "goal" : "manual", sessionName);
  });

  pi.on("session_shutdown", async () => {
    sessionGoalGeneration += 1;
    sessionGoalRunning?.controller.abort();
  });

  pi.on("session_tree", async (_event, ctx) => {
    resetSessionGoalLifecycle(ctx);
    if (!inTmux()) return;
    await serializeGoalOperation(() => applyRestoredVisibleIdentity(pi, ctx));
  });

  pi.on("before_agent_start", async (event, ctx) => {
    const notes = [];
    const cwd = await boundWorktreePath(pi, event.systemPromptOptions.cwd || ctx.cwd);
    if (!currentSessionGoal) startInitialSessionGoalEvaluation(pi, event.prompt, cwd, ctx);

    if (REPO_START_TRIGGERS.test(event.prompt) && await onMainBranch(pi, cwd)) {
      notes.push("You are on main. Before changing files, run `repo-start <branch>` and continue from the created worktree.");
    }

    if (await needsSubjectReminder(pi) && !await setSubjectFromSubagent(pi, event.prompt, cwd, ctx.signal)) {
      notes.push("Choose a concise task subject, then run `tmux-agent-subject set \"<short subject>\"` before continuing. The provisional label will be replaced by the feature branch.");
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
      const reason = await bashCommandBlockReason(pi, event.input.command || "", ctx.cwd);
      if (reason) return { block: true, reason };
      return;
    }

    if (event.toolName === "edit" || event.toolName === "write") {
      await updateCurrentSpec(pi, event, ctx);
    }
  });

  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "bash") return;
    if (event.isError) return;
    await syncSessionNameFromTmux(pi, ctx);
    await updateCurrentSpecFromBash(pi, event, ctx);
  });
}
