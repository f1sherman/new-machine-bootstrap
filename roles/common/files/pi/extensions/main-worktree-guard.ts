import fs from "node:fs";
import path from "node:path";

const COMMAND_TIMEOUT_MS = 5000;
const FILE_MUTATORS = new Set([
  "rm", "mv", "cp", "install", "touch", "mkdir", "rmdir", "ln",
  "truncate", "patch", "chmod", "chown",
]);
const DESTINATION_ONLY_MUTATORS = new Set(["cp", "install", "ln"]);
const GIT_WORKTREE_MUTATORS = new Set([
  "restore", "clean", "reset", "checkout", "switch", "apply",
]);

async function exec(pi, command, args, options = {}) {
  return pi.exec(command, args, { timeout: COMMAND_TIMEOUT_MS, ...options });
}

function expandHome(filePath) {
  if (filePath === "~") return process.env.HOME || filePath;
  if (filePath.startsWith("~/")) return path.join(process.env.HOME || "", filePath.slice(2));
  return filePath;
}

function probeDir(filePath, fallbackCwd) {
  const expanded = expandHome(filePath || fallbackCwd);
  let probe = path.isAbsolute(expanded) ? expanded : path.resolve(fallbackCwd, expanded);
  if (!fs.existsSync(probe) || !fs.statSync(probe).isDirectory()) probe = path.dirname(probe);
  while (!fs.existsSync(probe) && probe !== path.dirname(probe)) probe = path.dirname(probe);
  return fs.existsSync(probe) ? probe : fallbackCwd;
}

async function gitValue(pi, cwd, args) {
  const result = await exec(pi, "git", ["-C", cwd, ...args]);
  return result.code === 0 ? result.stdout.trim() : "";
}

function absoluteGitPath(value, cwd) {
  return path.resolve(cwd, value);
}

async function protectedMainWorktree(pi, candidate, fallbackCwd) {
  const cwd = probeDir(candidate, fallbackCwd);
  const root = await gitValue(pi, cwd, ["rev-parse", "--show-toplevel"]);
  if (!root) return "";
  const branch = await gitValue(pi, root, ["branch", "--show-current"]);
  if (branch !== "main") return "";
  const gitDir = await gitValue(pi, root, ["rev-parse", "--git-dir"]);
  const commonDir = await gitValue(pi, root, ["rev-parse", "--git-common-dir"]);
  if (!gitDir || !commonDir) return "";
  return absoluteGitPath(gitDir, root) === absoluteGitPath(commonDir, root) ? root : "";
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
  for (let index = 0; index < command.length; index += 1) {
    const character = command[index];
    if (escaped) {
      current += character;
      escaped = false;
      continue;
    }
    if (character === "\\" && quote !== "'") {
      current += character;
      escaped = true;
      continue;
    }
    if (quote) {
      current += character;
      if (character === quote) quote = "";
      continue;
    }
    if (character === "'" || character === '"') {
      current += character;
      quote = character;
      continue;
    }
    if (";&|()\n\r".includes(character)) {
      if (current.trim()) segments.push(current.trim());
      current = "";
      if ((character === "&" || character === "|") && command[index + 1] === character) index += 1;
      continue;
    }
    current += character;
  }
  if (current.trim()) segments.push(current.trim());
  return segments;
}

function shellTokens(segment) {
  const tokens = [];
  let current = "";
  let quote = "";
  let escaped = false;
  for (const character of segment) {
    if (escaped) {
      current += character;
      escaped = false;
    } else if (character === "\\" && quote !== "'") {
      escaped = true;
    } else if (quote) {
      if (character === quote) quote = "";
      else current += character;
    } else if (character === "'" || character === '"') {
      quote = character;
    } else if (/\s/.test(character)) {
      if (current) tokens.push(current);
      current = "";
    } else {
      current += character;
    }
  }
  if (current) tokens.push(current);
  return tokens;
}

function commandIndex(tokens, commands) {
  for (let index = 0; index < tokens.length; index += 1) {
    if (commands.has(path.basename(tokens[index]))) return index;
  }
  return -1;
}

function changedDirectory(segment, cwd) {
  const tokens = shellTokens(segment);
  if (tokens[0] !== "cd" || !tokens[1]) return "";
  const target = expandHome(tokens[1] === "--" ? tokens[2] : tokens[1]);
  if (!target) return "";
  return path.isAbsolute(target) ? target : path.resolve(cwd, target);
}

function resolveCandidate(candidate, cwd) {
  const expanded = expandHome(candidate.replace(/^['"]|['"]$/g, ""));
  return path.isAbsolute(expanded) ? expanded : path.resolve(cwd, expanded);
}

function positionalOperands(tokens, start) {
  const operands = [];
  let optionsDone = false;
  for (let index = start; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!optionsDone && token === "--") {
      optionsDone = true;
      continue;
    }
    if (!optionsDone && token.startsWith("-")) continue;
    operands.push(token);
  }
  return operands;
}

function redirectionTargets(segment) {
  const targets = [];
  const pattern = /(?:^|[^>])>>?\s*(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))/g;
  for (const match of segment.matchAll(pattern)) targets.push(match[1] || match[2] || match[3]);
  return targets;
}

function explicitPaths(command) {
  const paths = [];
  const pattern = /["'](\/[^"']+)["']|(?:^|[\s(=])(\/[^\s;&|()<>"']+)/g;
  for (const match of command.matchAll(pattern)) paths.push(match[1] || match[2]);
  return paths;
}

function gitMutationCwd(tokens, fallbackCwd) {
  const gitIndex = commandIndex(tokens, new Set(["git"]));
  if (gitIndex === -1) return undefined;
  let cwd = fallbackCwd;
  let subcommand = "";
  for (let index = gitIndex + 1; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token === "-C" && tokens[index + 1]) {
      cwd = resolveCandidate(tokens[++index], cwd);
      continue;
    }
    if (token.startsWith("-C") && token.length > 2) {
      cwd = resolveCandidate(token.slice(2), cwd);
      continue;
    }
    if (!token.startsWith("-")) {
      subcommand = token;
      break;
    }
  }
  return GIT_WORKTREE_MUTATORS.has(subcommand) ? cwd : undefined;
}

function interpreterWrites(command) {
  return /\.(?:write_text|write_bytes)\s*\(|\bopen\s*\([^)]*,\s*["'][wax+]|\bFile\.(?:write|binwrite|open)\s*\(|\b(?:writeFile|writeFileSync|appendFile|appendFileSync)\s*\(/s.test(command);
}

function blockReason(category, root) {
  return `Blocked ${category} targeting primary main worktree ${root}. Start or use a linked feature worktree.`;
}

async function firstProtectedRoot(pi, candidates, cwd) {
  for (const candidate of candidates) {
    const root = await protectedMainWorktree(pi, resolveCandidate(candidate, cwd), cwd);
    if (root) return root;
  }
  return "";
}

async function bashMutationBlockReason(pi, command, initialCwd) {
  if (interpreterWrites(command)) {
    const candidates = explicitPaths(command);
    if (candidates.length === 0) candidates.push(initialCwd);
    const root = await firstProtectedRoot(pi, candidates, initialCwd);
    if (root) return blockReason("interpreter file write", root);
  }

  let cwd = initialCwd;
  for (const segment of splitShellSegments(command)) {
    const payload = shellWrappedPayload(segment);
    if (payload) {
      const nestedReason = await bashMutationBlockReason(pi, payload, cwd);
      if (nestedReason) return nestedReason;
      continue;
    }

    const nextCwd = changedDirectory(segment, cwd);
    if (nextCwd) {
      cwd = nextCwd;
      continue;
    }

    const redirected = redirectionTargets(segment);
    if (redirected.length > 0) {
      const root = await firstProtectedRoot(pi, redirected, cwd);
      if (root) return blockReason("shell redirection", root);
    }

    const tokens = shellTokens(segment);
    const gitCwd = gitMutationCwd(tokens, cwd);
    if (gitCwd) {
      const root = await protectedMainWorktree(pi, gitCwd, cwd);
      if (root) return blockReason("Git working-tree mutation", root);
    }

    const teeIndex = commandIndex(tokens, new Set(["tee"]));
    if (teeIndex !== -1) {
      const root = await firstProtectedRoot(pi, positionalOperands(tokens, teeIndex + 1), cwd);
      if (root) return blockReason("tee output", root);
    }

    const mutatorIndex = commandIndex(tokens, FILE_MUTATORS);
    if (mutatorIndex !== -1) {
      const mutator = path.basename(tokens[mutatorIndex]);
      let operands = positionalOperands(tokens, mutatorIndex + 1);
      if (DESTINATION_ONLY_MUTATORS.has(mutator) && operands.length > 0) operands = [operands.at(-1)];
      const root = await firstProtectedRoot(pi, operands.length > 0 ? operands : [cwd], cwd);
      if (root) return blockReason(`${mutator} mutation`, root);
    }

    const sedIndex = commandIndex(tokens, new Set(["sed", "perl"]));
    if (sedIndex !== -1 && tokens.slice(sedIndex + 1).some((token) => /^-[^-]*i/.test(token) || token === "--in-place" || token.startsWith("--in-place="))) {
      const operands = positionalOperands(tokens, sedIndex + 1);
      const root = await firstProtectedRoot(pi, operands.length > 0 ? [operands.at(-1)] : [cwd], cwd);
      if (root) return blockReason("in-place edit", root);
    }
  }
  return "";
}

export default function mainWorktreeGuard(pi) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "edit" || event.toolName === "write") {
      const targetPath = event.input.path || event.input.file_path || "";
      const root = await protectedMainWorktree(pi, targetPath, ctx.cwd);
      if (root) return { block: true, reason: blockReason(`${event.toolName} file change`, root) };
      return;
    }
    if (event.toolName === "bash") {
      const reason = await bashMutationBlockReason(pi, event.input.command || "", ctx.cwd);
      if (reason) return { block: true, reason };
    }
  });
}
