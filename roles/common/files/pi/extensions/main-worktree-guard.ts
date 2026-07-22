import fs from "node:fs";
import path from "node:path";

const COMMAND_TIMEOUT_MS = 5000;
const FILE_MUTATORS = new Set([
  "rm", "mv", "cp", "install", "touch", "mkdir", "rmdir", "ln",
  "truncate", "patch", "chmod", "chown",
]);
const DESTINATION_ONLY_MUTATORS = new Set(["cp", "install", "ln"]);
const TARGET_DIRECTORY_MUTATORS = new Set(["cp", "install", "ln", "mv"]);
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

function probeDirs(filePath, fallbackCwd, followFinalSymlink = true) {
  const expanded = expandHome(filePath || fallbackCwd);
  const absolute = path.isAbsolute(expanded) ? expanded : path.resolve(fallbackCwd, expanded);
  let probe = path.isAbsolute(expanded) ? expanded : path.resolve(fallbackCwd, expanded);
  let lexical = "";
  while (probe !== path.dirname(probe)) {
    if (fs.existsSync(probe)) {
      const entry = fs.lstatSync(probe);
      if (entry.isDirectory() && !entry.isSymbolicLink()) {
        lexical = probe;
        break;
      }
    }
    probe = path.dirname(probe);
  }
  if (!lexical) lexical = fs.existsSync(probe) ? probe : fallbackCwd;

  probe = absolute;
  const finalIsSymlink = fs.existsSync(absolute) && fs.lstatSync(absolute).isSymbolicLink();
  while (!fs.existsSync(probe) && probe !== path.dirname(probe)) probe = path.dirname(probe);
  let resolved = "";
  if (fs.existsSync(probe) && (followFinalSymlink || !finalIsSymlink)) {
    const real = fs.realpathSync(probe);
    resolved = fs.statSync(real).isDirectory() ? real : path.dirname(real);
  }
  return [...new Set([lexical, resolved].filter(Boolean))];
}

async function gitValue(pi, cwd, args) {
  const result = await exec(pi, "git", ["-C", cwd, ...args]);
  return result.code === 0 ? result.stdout.trim() : "";
}

function absoluteGitPath(value, cwd) {
  return path.resolve(cwd, value);
}

async function protectedMainWorktree(pi, candidate, fallbackCwd, options = {}) {
  for (const cwd of probeDirs(candidate, fallbackCwd, options.followFinalSymlink !== false)) {
    const root = await gitValue(pi, cwd, ["rev-parse", "--show-toplevel"]);
    if (!root) continue;
    const branch = await gitValue(pi, root, ["branch", "--show-current"]);
    if (branch !== "main") continue;
    const gitDir = await gitValue(pi, root, ["rev-parse", "--git-dir"]);
    const commonDir = await gitValue(pi, root, ["rev-parse", "--git-common-dir"]);
    if (!gitDir || !commonDir) continue;
    if (absoluteGitPath(gitDir, root) === absoluteGitPath(commonDir, root)) return root;
  }
  return "";
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
    if (character === "|" && current.endsWith(">")) {
      current += character;
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

function executableIndex(tokens) {
  let index = 0;
  while (index < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[index])) index += 1;
  if (tokens[index] === "command") index += 1;
  if (tokens[index] === "env") {
    index += 1;
    while (index < tokens.length) {
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[index])) {
        index += 1;
      } else if (["-u", "--unset", "-C", "--chdir", "-S", "--split-string"].includes(tokens[index])) {
        index += 2;
      } else if (tokens[index].startsWith("-")) {
        index += 1;
      } else {
        break;
      }
    }
  }
  if (tokens[index] === "sudo") {
    index += 1;
    while (index < tokens.length && tokens[index].startsWith("-")) index += 1;
  }
  if (tokens[index] === "time") {
    index += 1;
    while (index < tokens.length && tokens[index].startsWith("-")) index += 1;
  }
  return index;
}

function changedDirectory(segment, cwd) {
  const tokens = shellTokens(segment);
  const index = executableIndex(tokens);
  if (path.basename(tokens[index] || "") !== "cd" || !tokens[index + 1]) return "";
  const target = expandHome(tokens[index + 1] === "--" ? tokens[index + 2] : tokens[index + 1]);
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
  let quote = "";
  let escaped = false;
  for (let index = 0; index < segment.length; index += 1) {
    const character = segment[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (character === "\\" && quote !== "'") {
      escaped = true;
      continue;
    }
    if (quote) {
      if (character === quote) quote = "";
      continue;
    }
    if (character === "'" || character === '"') {
      quote = character;
      continue;
    }
    if (character !== ">") continue;
    if (segment[index + 1] === ">" || segment[index + 1] === "|") index += 1;
    while (/\s/.test(segment[index + 1] || "")) index += 1;
    const delimiter = segment[index + 1];
    let target = "";
    if (delimiter === "'" || delimiter === '"') {
      index += 2;
      while (index < segment.length && segment[index] !== delimiter) target += segment[index++];
    } else {
      index += 1;
      while (index < segment.length && !/[\s;&|()<>]/.test(segment[index])) target += segment[index++];
      index -= 1;
    }
    if (target) targets.push(target);
  }
  return targets;
}

function optionAwareOperands(tokens, start, valueOptions) {
  const operands = [];
  let optionsDone = false;
  for (let index = start; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!optionsDone && token === "--") {
      optionsDone = true;
      continue;
    }
    if (!optionsDone && valueOptions.has(token)) {
      index += 1;
      continue;
    }
    if (!optionsDone && [...valueOptions].some((option) => option.startsWith("--") && token.startsWith(`${option}=`))) continue;
    if (!optionsDone && token.startsWith("-")) continue;
    operands.push(token);
  }
  return operands;
}

function targetDirectoryOperand(tokens, start) {
  for (let index = start; index < tokens.length; index += 1) {
    const token = tokens[index];
    if ((token === "-t" || token === "--target-directory") && tokens[index + 1]) return tokens[index + 1];
    if (token.startsWith("--target-directory=")) return token.slice("--target-directory=".length);
    if (token.startsWith("-t") && token.length > 2) return token.slice(2);
  }
  return "";
}

function inPlaceTargets(tokens, start) {
  const operands = [];
  let scriptProvidedByOption = false;
  let optionsDone = false;
  for (let index = start; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!optionsDone && token === "--") {
      optionsDone = true;
      continue;
    }
    if (!optionsDone && ["-e", "--expression", "-f", "--file"].includes(token)) {
      scriptProvidedByOption = true;
      index += 1;
      continue;
    }
    if (!optionsDone && (token.startsWith("--expression=") || token.startsWith("--file="))) {
      scriptProvidedByOption = true;
      continue;
    }
    if (!optionsDone && token.startsWith("-")) continue;
    operands.push(token);
  }
  if (!scriptProvidedByOption) operands.shift();
  return operands;
}

function gitMutationCwd(tokens, fallbackCwd) {
  const gitIndex = executableIndex(tokens);
  if (path.basename(tokens[gitIndex] || "") !== "git") return undefined;
  let cwd = fallbackCwd;
  let workTree = "";
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
    if (token === "--work-tree" && tokens[index + 1]) {
      workTree = resolveCandidate(tokens[++index], cwd);
      continue;
    }
    if (token.startsWith("--work-tree=")) {
      workTree = resolveCandidate(token.slice("--work-tree=".length), cwd);
      continue;
    }
    if (["-c", "--config-env", "--git-dir", "--namespace", "--exec-path"].includes(token)) {
      index += 1;
      continue;
    }
    if (token.startsWith("--git-dir=") || token.startsWith("--namespace=") || token.startsWith("--config-env=") || token.startsWith("--exec-path=")) continue;
    if (!token.startsWith("-")) {
      subcommand = token;
      break;
    }
  }
  return GIT_WORKTREE_MUTATORS.has(subcommand) ? (workTree || cwd) : undefined;
}

function mutationTargets(commandName, tokens, start, cwd) {
  if (commandName === "chmod") {
    const operands = [];
    let usesReference = false;
    let optionsDone = false;
    const flags = new Set(["-R", "--recursive", "-f", "--silent", "--quiet", "-v", "--verbose", "-c", "--changes", "--preserve-root", "--no-preserve-root"]);
    for (let index = start; index < tokens.length; index += 1) {
      const token = tokens[index];
      if (!optionsDone && token === "--") {
        optionsDone = true;
      } else if (!optionsDone && token === "--reference" && tokens[index + 1]) {
        usesReference = true;
        index += 1;
      } else if (!optionsDone && token.startsWith("--reference=")) {
        usesReference = true;
      } else if (!optionsDone && (flags.has(token) || /^-[Rfvc]+$/.test(token))) {
        continue;
      } else {
        operands.push(token);
      }
    }
    if (!usesReference) operands.shift();
    return operands;
  }
  if (commandName === "chown") {
    const referenceOptions = new Set(["--reference"]);
    const usesReference = tokens.slice(start).some((token) => token === "--reference" || token.startsWith("--reference="));
    const operands = optionAwareOperands(tokens, start, referenceOptions);
    if (!usesReference) operands.shift();
    return operands;
  }
  if (commandName === "touch") {
    return optionAwareOperands(tokens, start, new Set(["-r", "--reference", "-d", "--date", "-t"]));
  }
  if (commandName === "truncate") {
    return optionAwareOperands(tokens, start, new Set(["-s", "--size", "-r", "--reference"]));
  }
  if (commandName === "patch") {
    for (let index = start; index < tokens.length; index += 1) {
      if (["-d", "--directory", "-o", "--output"].includes(tokens[index]) && tokens[index + 1]) return [tokens[index + 1]];
      if (tokens[index].startsWith("--directory=")) return [tokens[index].slice("--directory=".length)];
      if (tokens[index].startsWith("--output=")) return [tokens[index].slice("--output=".length)];
    }
    const valueOptions = new Set(["-d", "--directory", "-o", "--output", "-i", "--input", "-r", "--reject-file", "-B", "--prefix", "-Y", "--basename-prefix", "-z", "--suffix"]);
    const operands = optionAwareOperands(tokens, start, valueOptions);
    return operands.length > 0 ? [operands[0]] : [cwd];
  }
  return positionalOperands(tokens, start);
}

function interpreterWriteTargets(command) {
  const targets = [];
  const addMatches = (pattern, modeIndex) => {
    for (const match of command.matchAll(pattern)) {
      if (modeIndex === undefined || /[wax+]/.test(match[modeIndex])) targets.push(match[2]);
    }
  };
  addMatches(/\bPath\s*\(\s*(["'])(.*?)\1\s*\)\s*\.\s*(?:write_text|write_bytes)\s*\(/gs);
  addMatches(/\bopen\s*\(\s*(["'])(.*?)\1\s*,\s*(["'])(.*?)\3/gs, 4);
  addMatches(/\bFile\.(?:write|binwrite)\s*\(\s*(["'])(.*?)\1/gs);
  addMatches(/\bFile\.open\s*\(\s*(["'])(.*?)\1\s*,\s*(["'])(.*?)\3/gs, 4);
  addMatches(/\b(?:writeFile|writeFileSync|appendFile|appendFileSync)\s*\(\s*(["'])(.*?)\1/gs);
  return targets;
}

function blockReason(category, root) {
  return `Blocked ${category} targeting primary main worktree ${root}. Start or use a linked feature worktree.`;
}

async function firstProtectedRoot(pi, candidates, cwd, options = {}) {
  for (const candidate of candidates) {
    const root = await protectedMainWorktree(pi, resolveCandidate(candidate, cwd), cwd, options);
    if (root) return root;
  }
  return "";
}

async function interpreterHeredocBlockReason(pi, command, initialCwd) {
  let cwd = initialCwd;
  let heredoc;
  for (const line of command.split(/\r?\n/)) {
    if (heredoc) {
      if (line.trim() === heredoc.marker) {
        const root = await firstProtectedRoot(pi, interpreterWriteTargets(heredoc.body.join("\n")), heredoc.cwd);
        if (root) return blockReason("interpreter file write", root);
        heredoc = undefined;
      } else {
        heredoc.body.push(line);
      }
      continue;
    }
    for (const segment of splitShellSegments(line)) {
      const nextCwd = changedDirectory(segment, cwd);
      if (nextCwd) {
        cwd = nextCwd;
        continue;
      }
      const tokens = shellTokens(segment);
      const executable = executableIndex(tokens);
      const commandName = path.basename(tokens[executable] || "");
      if (!/^(?:python(?:\d+(?:\.\d+)*)?|ruby|node|nodejs)$/.test(commandName)) continue;
      const match = segment.match(/<<-?\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/);
      if (match) heredoc = { marker: match[1], cwd, body: [] };
    }
  }
  return "";
}

async function bashMutationBlockReason(pi, command, initialCwd) {
  const heredocReason = await interpreterHeredocBlockReason(pi, command, initialCwd);
  if (heredocReason) return heredocReason;

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

    const executable = executableIndex(tokens);
    const commandName = path.basename(tokens[executable] || "");
    if (/^(?:python(?:\d+(?:\.\d+)*)?|ruby|node|nodejs)$/.test(commandName)) {
      const interpreterTargets = interpreterWriteTargets(segment);
      const root = await firstProtectedRoot(pi, interpreterTargets, cwd);
      if (root) return blockReason("interpreter file write", root);
    }

    if (commandName === "tee") {
      const root = await firstProtectedRoot(pi, positionalOperands(tokens, executable + 1), cwd);
      if (root) return blockReason("tee output", root);
    }

    if (FILE_MUTATORS.has(commandName)) {
      let operands = mutationTargets(commandName, tokens, executable + 1, cwd);
      const targetDirectory = TARGET_DIRECTORY_MUTATORS.has(commandName) ? targetDirectoryOperand(tokens, executable + 1) : "";
      if (targetDirectory) {
        operands = commandName === "mv" ? [...operands, targetDirectory] : [targetDirectory];
      } else if (DESTINATION_ONLY_MUTATORS.has(commandName) && operands.length > 0) {
        operands = [operands.at(-1)];
      }
      const root = await firstProtectedRoot(
        pi,
        operands.length > 0 ? operands : [cwd],
        cwd,
        { followFinalSymlink: commandName !== "rm" },
      );
      if (root) return blockReason(`${commandName} mutation`, root);
    }

    if ((commandName === "sed" || commandName === "perl") && tokens.slice(executable + 1).some((token) => /^-[^-]*i/.test(token) || token === "--in-place" || token.startsWith("--in-place="))) {
      const targets = inPlaceTargets(tokens, executable + 1);
      const root = await firstProtectedRoot(pi, targets.length > 0 ? targets : [cwd], cwd);
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
