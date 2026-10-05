import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFile, execFileSync } from 'node:child_process';
import { promisify, parseArgs } from 'node:util';
import { loadDefinition, root } from './definition.mjs';

const { values } = parseArgs({ options: {
  model: { type: 'string' },
  trials: { type: 'string', default: '3' },
  'compare-ref': { type: 'string' },
  'description-file': { type: 'string' },
  case: { type: 'string' },
  output: { type: 'string', default: 'tmp/session-naming-eval.json' },
  help: { type: 'boolean' },
} });
if (values.help) {
  console.log('Usage: node evals/session-naming/run.mjs --model <provider/model> [--trials 3] [--compare-ref <commit>] [--case <id>] [--description-file <path>] [--output <path>]');
  process.exit(0);
}
const model = values.model || process.env.PI_MODEL;
if (!model) throw new Error('Supply --model or PI_MODEL; evals make paid model calls');
const trials = Number(values.trials);
if (!Number.isSafeInteger(trials) || trials < 1) throw new Error('--trials must be a positive integer');
let cases = JSON.parse(fs.readFileSync(new URL('./cases.json', import.meta.url), 'utf8'));
if (values.case) cases = cases.filter(item => item.id === values.case);
if (!cases.length) throw new Error('No matching eval cases');
const output = path.resolve(values.output);
fs.mkdirSync(path.dirname(output), { recursive: true });
const baseline = values['compare-ref']
  ? execFileSync('git', ['rev-parse', '--verify', '--end-of-options', `${values['compare-ref']}^{commit}`], { cwd: root, encoding: 'utf8' }).trim()
  : undefined;
const descriptionFile = values['description-file'] ? path.resolve(values['description-file']) : undefined;
const variants = baseline ? [{ id: 'baseline', ref: baseline }, { id: 'current' }] : [{ id: 'current' }];
const report = { model, thinking: 'low', trials, startedAt: new Date().toISOString(), variants: [], results: [] };
for (const variant of variants) {
  const definition = await loadDefinition(variant.ref);
  const description = variant.id === 'current' && descriptionFile
    ? fs.readFileSync(descriptionFile, 'utf8') : definition.description;
  report.variants.push({ ...variant, descriptionFile: variant.id === 'current' ? descriptionFile : undefined,
    descriptionCharacters: description.length,
    descriptionSha256: crypto.createHash('sha256').update(description).digest('hex'),
  });
}
const save = () => fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`);
const run = promisify(execFile);

async function evaluate(variant, scenario) {
  const env = { ...process.env };
  delete env.SESSION_NAMING_EVAL_REF;
  delete env.SESSION_NAMING_EVAL_DESCRIPTION_FILE;
  if (variant.ref) env.SESSION_NAMING_EVAL_REF = variant.ref;
  if (variant.id === 'current' && descriptionFile) env.SESSION_NAMING_EVAL_DESCRIPTION_FILE = descriptionFile;
  const pending = run('pi', [
    '--mode', 'json', '--no-session', '--no-extensions', '--no-skills',
    '--no-context-files', '--no-prompt-templates', '--no-themes', '--no-builtin-tools',
    '--extension', path.join(root, 'evals/session-naming/tool.ts'),
    '--tools', 'set_session_name', '--model', model, '--thinking', 'low',
    '--system-prompt', 'You are an assistant continuing the session described below. Handle the user request. Use available tools when appropriate. Do not claim to have performed unavailable external actions.',
    `Prior session context:\n${scenario.context}\n\nCurrent user request:\n${scenario.request}`,
  ], { cwd: root, env, timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
  // Pi consumes piped stdin before the supplied prompt.
  pending.child.stdin.end();
  const { stdout, stderr } = await pending;
  const events = stdout.split('\n').filter(line => line.trim()).map(line => JSON.parse(line));
  const declaredTools = events.filter(event => event.type === 'message_end' && event.message?.role === 'system')
    .flatMap(event => event.message.toolsAdded || []);
  if (!declaredTools.some(tool => tool.name === 'set_session_name')) {
    throw new Error(`Naming tool was not declared: ${stderr}`);
  }
  const assistants = events.filter(event => event.type === 'message_end' && event.message?.role === 'assistant').map(event => event.message);
  const failures = events.filter(event => event.type === 'extension_error' || (event.type === 'tool_execution_end' && event.isError));
  if (!assistants.length || failures.length || assistants.some(message => ['error', 'aborted'].includes(message.stopReason))) {
    throw new Error(`Model/tool failure: ${JSON.stringify(failures)} ${assistants.map(message => message.errorMessage || message.stopReason).join('; ')} ${stderr}`);
  }
  if (!events.some(event => event.type === 'agent_settled')) throw new Error(`Incomplete JSON event stream: ${stderr}`);
  const started = events.filter(event => event.type === 'tool_execution_start');
  const completed = events.filter(event => event.type === 'tool_execution_end');
  if (started.length !== completed.length || started.some(start =>
    !completed.some(end => end.toolCallId === start.toolCallId))) {
    throw new Error('Incomplete tool execution');
  }
  const calls = started.map(event => ({ tool: event.toolName, args: event.args }));
  const usage = assistants[0].usage;
  const inputTokens = usage && usage.input + usage.cacheRead + usage.cacheWrite;
  if (!Number.isFinite(inputTokens) || inputTokens <= 0) throw new Error('Missing first-request provider input usage');
  const passed = calls.length === scenario.calls && calls.every(call =>
    call.tool === 'set_session_name' && typeof call.args?.name === 'string' &&
    call.args.name.trim().length > 0 && call.args.name.length <= 80 &&
    (!scenario.name || call.args.name === scenario.name) &&
    (!scenario.previousName || call.args.name !== scenario.previousName));
  return { passed, expectedCalls: scenario.calls, expectedName: scenario.name,
    previousName: scenario.previousName, calls,
    provider: assistants[0].provider, model: assistants[0].model, inputTokens,
    firstRequestUsage: usage,
    response: assistants.flatMap(message => message.content.filter(block => block.type === 'text').map(block => block.text)).join('\n'),
  };
}

try {
  for (let trial = 1; trial <= trials; trial++) {
    for (const scenario of cases) {
      for (const variant of variants) {
        let result;
        try {
          result = await evaluate(variant, scenario);
        } catch (error) {
          report.results.push({ variant: variant.id, case: scenario.id, trial, error: error.message,
            stdout: error.stdout, stderr: error.stderr });
          if (error.stdout) console.error(error.stdout);
          if (error.stderr) console.error(error.stderr);
          throw error;
        }
        report.results.push({ variant: variant.id, case: scenario.id, trial, ...result });
        save();
        console.log(`${result.passed ? 'PASS' : 'FAIL'} ${variant.id} ${scenario.id} trial=${trial} calls=${result.calls.length}/${scenario.calls} input=${result.inputTokens}`);
      }
    }
  }
  report.summary = report.variants.map(variant => {
    const rows = report.results.filter(row => row.variant === variant.id);
    return { variant: variant.id, passed: rows.filter(row => row.passed).length, total: rows.length,
      meanFirstRequestInputTokens: rows.reduce((total, row) => total + row.inputTokens, 0) / rows.length,
    };
  });
  if (baseline) {
    const [before, after] = report.summary;
    report.inputReduction = { meanTokens: before.meanFirstRequestInputTokens - after.meanFirstRequestInputTokens,
      percent: 100 * (1 - after.meanFirstRequestInputTokens / before.meanFirstRequestInputTokens) };
  }
  report.finishedAt = new Date().toISOString();
  console.log(JSON.stringify({ summary: report.summary, inputReduction: report.inputReduction, report: output }, null, 2));
  process.exitCode = report.results.some(row => row.variant === 'current' && !row.passed) ? 1 : 0;
} catch (error) {
  report.error = error.message;
  console.error(error.message);
  process.exitCode = 1;
} finally {
  save();
}
