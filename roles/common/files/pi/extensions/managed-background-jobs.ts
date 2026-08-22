import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { createBashToolDefinition } from "@earendil-works/pi-coding-agent";

const ADAPTERS_SYMBOL = Symbol.for("nmb.pi-managed-background-jobs.adapters");
const PROCESS_STATE_SYMBOL = Symbol.for("nmb.pi-managed-background-jobs.process-state");
const READ_ONLY_TOOLS = new Set(["read", "grep", "find", "ls"]);
const MANAGED_EXECUTABLES = new Set([
  "bin/provision", "./bin/provision",
  "bin/test", "./bin/test",
  "bin/test-ruby", "./bin/test-ruby",
]);
const SSH_VALUE_OPTIONS = new Set([
  "b", "c", "D", "e", "i", "L", "l", "m", "o", "p", "R", "w",
]);
const SSH_LOCAL_COMMAND_OPTIONS = new Set([
  "controlmaster", "controlpath", "controlpersist", "forkafterauthentication",
  "knownhostscommand", "localcommand", "permitlocalcommand", "pkcs11provider",
  "proxycommand", "proxyjump", "securitykeyprovider",
]);
const SSH_FLAG_OPTIONS = new Set([
  "4", "6", "A", "a", "C", "g", "K", "k", "M", "n", "q", "T",
  "t", "v", "X", "x", "Y", "y",
]);
const SSH_REMOTE_EXPANSION_CHARACTERS = new Set([
  "$", "`", "*", "?", "[", "]", "{", "}", "~",
]);
const COMPLETION_TAIL_BYTES = 16 * 1024;
const COMPLETION_TAIL_LINES = 200;
const CANCEL_GRACE_MS = 5000;
const MAX_TIMEOUT_MS = 2_147_483_647;
const MAX_TIMEOUT_SECONDS = MAX_TIMEOUT_MS / 1000;

function shellWords(command, allowAnd = false) {
  const words = [];
  let word = "";
  let quote = "";
  let escaped = false;
  let started = false;

  const pushWord = () => {
    if (!started) return;
    words.push(word);
    word = "";
    started = false;
  };

  for (let index = 0; index < command.length; index += 1) {
    const character = command[index];
    if (escaped) {
      word += character;
      started = true;
      escaped = false;
      continue;
    }
    if (character === "\\" && quote !== "'") {
      escaped = true;
      started = true;
      continue;
    }
    if (quote) {
      if (character === quote) {
        quote = "";
      } else {
        if (quote === '"' && (character === "`"
          || (character === "$" && command[index + 1] === "("))) return undefined;
        word += character;
      }
      started = true;
      continue;
    }
    if (character === "'" || character === '"') {
      quote = character;
      started = true;
      continue;
    }
    if (character === "\n" || character === "\r") return undefined;
    if (/\s/.test(character)) {
      pushWord();
      continue;
    }
    if (character === "`" || (character === "$" && command[index + 1] === "(")) {
      return undefined;
    }
    if (character === "&" && command[index + 1] === "&" && allowAnd) {
      pushWord();
      words.push("&&");
      index += 1;
      continue;
    }
    if (";&|<>()".includes(character)) return undefined;
    word += character;
    started = true;
  }

  if (escaped || quote) return undefined;
  pushWord();
  return words;
}

function classifyRemoteCommand(remoteCommand) {
  const words = shellWords(remoteCommand, true);
  if (!words?.length) return false;
  const andIndexes = words.flatMap((word, index) => word === "&&" ? [index] : []);
  if (andIndexes.length === 0) return MANAGED_EXECUTABLES.has(words[0]);
  if (andIndexes.length !== 1 || andIndexes[0] !== 2) return false;
  return words[0] === "cd" && Boolean(words[1]) && MANAGED_EXECUTABLES.has(words[3]);
}

function unsafeSshOption(option, value) {
  if (option !== "o") return false;
  const name = value.trim().replace(/^=/, "").split(/(?:=|\s+)/, 1)[0].toLowerCase();
  return SSH_LOCAL_COMMAND_OPTIONS.has(name);
}

function sshRemoteStart(words) {
  let index = 1;
  let destinationFound = false;
  while (index < words.length) {
    const word = words[index];
    if (!destinationFound && word === "--") {
      index += 1;
      if (index >= words.length) return -1;
      destinationFound = true;
      index += 1;
      break;
    }
    if (!destinationFound && word.startsWith("-") && word !== "-") {
      const optionText = word.slice(1);
      if (!optionText) return -1;
      const option = optionText[0];
      if (SSH_VALUE_OPTIONS.has(option)) {
        let value = optionText.slice(1);
        if (!value) {
          index += 1;
          if (index >= words.length) return -1;
          value = words[index];
        }
        if (unsafeSshOption(option, value)) return -1;
        index += 1;
        continue;
      }
      if (![...optionText].every((flag) => SSH_FLAG_OPTIONS.has(flag))) return -1;
      index += 1;
      continue;
    }
    destinationFound = true;
    index += 1;
    break;
  }
  return destinationFound ? index : -1;
}

export function classifyManagedCommand(command) {
  const words = shellWords(command);
  if (!words?.length) return undefined;
  if (MANAGED_EXECUTABLES.has(words[0])) return { kind: "local", words };
  if (words[0] !== "ssh") return undefined;
  if (words.some((word) => [...word].some(
    (character) => SSH_REMOTE_EXPANSION_CHARACTERS.has(character),
  ))) return undefined;

  const remoteStart = sshRemoteStart(words);
  if (remoteStart < 0 || remoteStart >= words.length) return undefined;
  const remoteWords = words.slice(remoteStart);
  const remoteCommand = remoteWords.join(" ");
  if (!classifyRemoteCommand(remoteCommand)) return undefined;
  return { kind: "ssh", words, remoteCommand };
}

function shellQuote(word) {
  return `'${word.replaceAll("'", `'\\''`)}'`;
}

function managedExecutionCommand(command, classification) {
  if (classification.kind !== "ssh") return command;
  return [
    "ssh", "-F", "/dev/null",
    "-o", shellQuote("BatchMode=yes"),
    "-o", shellQuote("ControlMaster=no"),
    "-o", shellQuote("ControlPath=none"),
    "-o", shellQuote("ControlPersist=no"),
    "-o", shellQuote("ForkAfterAuthentication=no"),
    "-o", shellQuote("ProxyCommand=none"),
    "-o", shellQuote("PermitLocalCommand=no"),
    "-o", shellQuote("KnownHostsCommand=none"),
    ...classification.words.slice(1).map(shellQuote),
  ].join(" ");
}

function resolveTimeoutMs(timeout) {
  if (timeout === undefined) return undefined;
  if (!Number.isFinite(timeout) || timeout <= 0) {
    throw new Error("Invalid timeout: must be a finite number of seconds");
  }
  const timeoutMs = timeout * 1000;
  if (timeoutMs > MAX_TIMEOUT_MS) {
    throw new Error(`Invalid timeout: maximum is ${MAX_TIMEOUT_SECONDS} seconds`);
  }
  return timeoutMs;
}

function currentEnvironment(ctx) {
  const environment = { ...process.env };
  for (const name of [
    "PI_SESSION_ID", "PI_SESSION_FILE", "PI_PROVIDER", "PI_MODEL",
    "PI_REASONING_LEVEL",
  ]) delete environment[name];

  const sessionId = ctx.sessionManager.getSessionId();
  const sessionFile = ctx.sessionManager.getSessionFile();
  if (sessionId) environment.PI_SESSION_ID = sessionId;
  if (sessionFile) environment.PI_SESSION_FILE = sessionFile;
  if (ctx.model) {
    environment.PI_PROVIDER = ctx.model.provider;
    environment.PI_MODEL = ctx.model.id;
  }
  if (ctx.thinkingLevel) environment.PI_REASONING_LEVEL = ctx.thinkingLevel;
  return environment;
}

function defaultAdapters() {
  return {
    now: () => Date.now(),
    randomId: () => `bg-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
    makeLog(sessionId, jobId) {
      const safeSessionId = sessionId.replace(/[^A-Za-z0-9._-]/g, "_") || "ephemeral";
      const directory = path.join(os.tmpdir(), "pi-background-jobs", safeSessionId);
      fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
      fs.chmodSync(directory, 0o700);
      const logPath = path.join(directory, `${jobId}.log`);
      return { path: logPath, fd: fs.openSync(logPath, "wx", 0o600) };
    },
    spawn(command, options) {
      const shell = process.env.SHELL || "/bin/bash";
      const child = spawn(shell, ["-lc", command], {
        cwd: options.cwd,
        env: options.env,
        detached: true,
        stdio: ["ignore", options.logFd, options.logFd],
      });
      child.unref();
      return child;
    },
    async readTail(logPath, maxBytes) {
      const handle = await fs.promises.open(logPath, "r");
      try {
        const size = (await handle.stat()).size;
        const length = Math.min(size, maxBytes);
        const buffer = Buffer.alloc(length);
        await handle.read(buffer, 0, length, size - length);
        return buffer.toString("utf8");
      } finally {
        await handle.close();
      }
    },
    close: (fd) => fs.closeSync(fd),
    killProcessGroup: (pid, signal) => process.kill(-pid, signal),
    setTimeout: (callback, milliseconds) => setTimeout(callback, milliseconds),
    clearTimeout: (timer) => clearTimeout(timer),
    warn: (message) => console.warn(`[managed-background-jobs] ${message}`),
  };
}

function processState() {
  if (globalThis[PROCESS_STATE_SYMBOL]) return globalThis[PROCESS_STATE_SYMBOL];
  const created = { active: undefined, last: undefined, controller: undefined };
  globalThis[PROCESS_STATE_SYMBOL] = created;
  return created;
}

function textResult(text) {
  return { content: [{ type: "text", text }], details: undefined };
}

function boundedTail(tail) {
  return tail.split(/\r?\n/).slice(-COMPLETION_TAIL_LINES).join("\n");
}

function completionMessage(job, status, durationMs, tail) {
  const lines = [
    `Managed background job ${job.id} completed with ${status} after ${durationMs}ms.`,
    `Full log: ${job.logPath}`,
  ];
  if (tail) {
    const tailLines = tail.split("\n");
    const availableTailLines = COMPLETION_TAIL_LINES - lines.length - 2;
    lines.push("", "Output tail:", ...tailLines.slice(-availableTailLines));
  }
  return lines.join("\n");
}

export default function managedBackgroundJobs(pi) {
  const adapters = globalThis[ADAPTERS_SYMBOL] || defaultAdapters();
  const shared = processState();
  const builtIn = createBashToolDefinition(process.cwd());

  function applyGate(job) {
    const activeReadTools = job.savedActiveTools.filter((tool) => READ_ONLY_TOOLS.has(tool));
    pi.setActiveTools(activeReadTools);
  }

  function restoreTools(job) {
    if (job.toolsRestored) return;
    try {
      pi.setActiveTools(job.savedActiveTools);
      job.toolsRestored = true;
    } catch (error) {
      adapters.warn(`could not restore tools for ${job.id}: ${error.message}`);
    }
  }

  async function finishJob(job, code, signal) {
    if (job.finishing || job.finished || (job.terminationRequested && job.killTimer)) return;
    job.finishing = true;
    if (job.timeoutTimer) adapters.clearTimeout(job.timeoutTimer);

    const endedAt = adapters.now();
    let tail = "";
    if (!job.suppressCompletion) {
      try {
        tail = boundedTail(await adapters.readTail(job.logPath, COMPLETION_TAIL_BYTES));
      } catch (error) {
        adapters.warn(`could not read ${job.logPath}: ${error.message}`);
      }
    }

    if (job.suppressCompletion) {
      job.finished = true;
      job.finishing = false;
      if (shared.active === job) shared.active = undefined;
      return;
    }
    if (shared.controller?.finishJob !== finishJob) {
      job.finishing = false;
      return shared.controller?.finishJob(job, code, signal);
    }

    try {
      const status = job.timedOut
        ? `timeout after ${job.timeoutSeconds}s`
        : signal ? `signal ${signal}` : `exit ${code ?? "unknown"}`;
      const durationMs = Math.max(0, endedAt - job.startedAt);
      const completion = {
        id: job.id,
        pid: job.pid,
        command: job.command,
        cwd: job.cwd,
        startedAt: job.startedAt,
        endedAt,
        durationMs,
        code,
        signal,
        timedOut: job.timedOut,
        timeoutSeconds: job.timeoutSeconds,
        logPath: job.logPath,
        tail,
      };
      shared.last = completion;
      restoreTools(job);
      try {
        pi.sendMessage({
          customType: "managed-background-job-complete",
          content: completionMessage(job, status, durationMs, tail),
          display: true,
          details: completion,
        }, { triggerTurn: true, deliverAs: "steer" });
      } catch (error) {
        adapters.warn(`could not inject completion for ${job.id}: ${error.message}`);
      }
    } finally {
      restoreTools(job);
      job.finished = true;
      job.finishing = false;
      if (shared.active === job) shared.active = undefined;
    }
  }

  function terminateJob(job) {
    if (!job || job.finishing || job.finished) return false;
    job.terminationRequested = true;
    try {
      adapters.killProcessGroup(job.pid, "SIGTERM");
    } catch (error) {
      adapters.warn(`could not terminate ${job.id}: ${error.message}`);
    }
    if (!job.killTimer) {
      job.killTimer = adapters.setTimeout(() => {
        job.killTimer = undefined;
        try {
          adapters.killProcessGroup(job.pid, "SIGKILL");
        } catch (error) {
          adapters.warn(`could not kill ${job.id}: ${error.message}`);
        } finally {
          job.resolveTermination();
        }
        if (job.exited && !job.finished && job.exitResult) {
          const { code, signal } = job.exitResult;
          Promise.resolve(shared.controller?.finishJob(job, code, signal)).catch((error) => {
            adapters.warn(`completion failed for ${job.id}: ${error.message}`);
          });
        }
      }, CANCEL_GRACE_MS);
    }
    return true;
  }

  async function startManagedJob(command, classification, timeoutSeconds, ctx) {
    if (shared.active && !shared.active.finished) {
      throw new Error(`Managed background job ${shared.active.id} is already active.`);
    }

    const timeoutMs = resolveTimeoutMs(timeoutSeconds);

    const id = adapters.randomId();
    const startedAt = adapters.now();
    const sessionId = ctx.sessionManager.getSessionId() || "ephemeral";
    let log;
    try {
      log = adapters.makeLog(sessionId, id);
    } catch (error) {
      throw new Error(`Could not create a managed background job log: ${error.message}`);
    }

    let child;
    try {
      child = adapters.spawn(managedExecutionCommand(command, classification), {
        cwd: ctx.cwd,
        env: currentEnvironment(ctx),
        logFd: log.fd,
      });
    } catch (error) {
      try {
        adapters.close(log.fd);
      } catch (closeError) {
        adapters.warn(`could not close log descriptor for ${id}: ${closeError.message}`);
      }
      throw new Error(`Could not start managed background job ${id}: ${error.message}`);
    }
    try { adapters.close(log.fd); } catch (error) {
      adapters.warn(`could not close log descriptor for ${id}: ${error.message}`);
    }
    if (!child.pid) {
      child.once("error", (error) => {
        adapters.warn(`could not start ${id}: ${error.message}`);
      });
      throw new Error(`Could not start managed background job ${id}: child has no process ID.`);
    }

    const job = {
      id,
      child,
      pid: child.pid,
      command,
      cwd: ctx.cwd,
      startedAt,
      logPath: log.path,
      savedActiveTools: pi.getActiveTools(),
      finishing: false,
      finished: false,
      controller: undefined,
      toolsRestored: false,
      killTimer: undefined,
      timeoutTimer: undefined,
      timeoutSeconds,
      timedOut: false,
      suppressCompletion: false,
      terminationRequested: false,
      terminationPromise: undefined,
      resolveTermination: undefined,
      exited: false,
      exitResult: undefined,
      resolveExit: undefined,
      exitPromise: undefined,
    };
    job.exitPromise = new Promise((resolve) => { job.resolveExit = resolve; });
    job.terminationPromise = new Promise((resolve) => { job.resolveTermination = resolve; });
    job.controller = shared.controller;
    shared.active = job;
    if (timeoutMs !== undefined) {
      job.timeoutTimer = adapters.setTimeout(() => {
        if (shared.active !== job || job.finishing || job.finished) return;
        job.timedOut = true;
        terminateJob(job);
      }, timeoutMs);
    }
    const finishFromChild = (code, signal) => {
      if (!job.exited) {
        job.exited = true;
        job.exitResult = { code, signal };
        job.resolveExit();
      }
      if (!job.terminationRequested || !job.killTimer) {
        Promise.resolve(shared.controller?.finishJob(job, code, signal)).catch((error) => {
          adapters.warn(`completion failed for ${job.id}: ${error.message}`);
        });
      }
    };
    child.once("exit", finishFromChild);
    child.once("error", (error) => {
      adapters.warn(`child process failed for ${job.id}: ${error.message}`);
      finishFromChild(null, null);
    });
    applyGate(job);
    return textResult(`Managed background job ${id} started.\nPID: ${job.pid}\nCommand: ${command}\nFull log: ${log.path}`);
  }

  shared.controller = { finishJob, terminateJob, applyGate };

  pi.registerTool({
    ...builtIn,
    executionMode: "sequential",
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const classification = classifyManagedCommand(params.command);
      if (!classification) {
        const contextualBuiltIn = createBashToolDefinition(ctx.cwd);
        return contextualBuiltIn.execute(toolCallId, params, signal, onUpdate, ctx);
      }
      return startManagedJob(params.command, classification, params.timeout, ctx);
    },
  });

  pi.on("tool_call", (event) => {
    if (!shared.active || READ_ONLY_TOOLS.has(event.toolName)) return undefined;
    return {
      block: true,
      reason: "A managed background job is active. Only read-only inspection tools are available.",
      terminate: false,
    };
  });

  pi.on("session_start", () => {
    shared.controller = { finishJob, terminateJob, applyGate };
    if (shared.active && !shared.active.finished) {
      applyGate(shared.active);
      if (shared.active.exitResult && !shared.active.finishing) {
        const { code, signal } = shared.active.exitResult;
        Promise.resolve(finishJob(shared.active, code, signal)).catch((error) => {
          adapters.warn(`completion failed for ${shared.active?.id || "managed job"}: ${error.message}`);
        });
      }
    }
  });

  const blockSessionChange = (_event, ctx) => {
    if (!shared.active) return undefined;
    ctx.ui.notify(`Managed background job ${shared.active.id} is still active.`, "warning");
    return { cancel: true };
  };
  pi.on("session_before_switch", blockSessionChange);
  pi.on("session_before_fork", blockSessionChange);

  pi.on("session_shutdown", async (event) => {
    if (event.reason === "reload") {
      shared.controller = undefined;
      return;
    }
    const job = shared.active;
    if (!job || job.finished) return;
    job.suppressCompletion = true;
    const terminationStarted = terminateJob(job);
    if (terminationStarted) await job.terminationPromise;
    await job.exitPromise;
  });

  pi.registerCommand("background-jobs", {
    description: "Show the active or most recent managed background job",
    handler: async (_args, ctx) => {
      if (shared.active) {
        ctx.ui.notify(`Managed background job ${shared.active.id} is active. Log: ${shared.active.logPath}`, "info");
      } else if (shared.last) {
        ctx.ui.notify(`Managed background job ${shared.last.id} completed. Log: ${shared.last.logPath}`, "info");
      } else {
        ctx.ui.notify("No managed background job is available.", "info");
      }
    },
  });

  pi.registerCommand("background-cancel", {
    description: "Cancel the active managed background job",
    handler: async (_args, ctx) => {
      if (terminateJob(shared.active)) {
        ctx.ui.notify(`Cancellation requested for managed background job ${shared.active.id}.`, "warning");
      } else {
        ctx.ui.notify("No managed background job is active.", "info");
      }
    },
  });
}
