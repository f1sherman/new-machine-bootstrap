import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { parseArgs } from 'node:util';
import { loadDefinition, root } from './definition.mjs';

const { values } = parseArgs({ options: {
  model: { type: 'string' }, trials: { type: 'string', default: '1' },
  'compare-ref': { type: 'string' }, ablate: { type: 'boolean' },
  'stage-only': { type: 'boolean' },
  'docker-subnet': { type: 'string' },
  harbor: { type: 'string', default: 'harbor' },
  output: { type: 'string', default: 'tmp/session-naming-harbor' },
  help: { type: 'boolean' },
} });
if (values.help) {
  console.log('Usage: node evals/session-naming/run.mjs --model provider/model\n  [--trials 1] [--compare-ref ref] [--ablate] [--stage-only]\n  [--harbor path] [--docker-subnet CIDR] [--output tmp/session-naming-harbor]');
  process.exit(0);
}
const model = values.model;
if (!model || !/^(openai|anthropic)\/[A-Za-z0-9][A-Za-z0-9._:-]*$/.test(model)) {
  throw new Error('Supply --model openai/model or anthropic/model explicitly; live runs make paid calls');
}
const trials = Number(values.trials);
if (!Number.isSafeInteger(trials) || trials < 1) throw new Error('--trials must be a positive integer');
const output = path.resolve(root, values.output);
if (!output.startsWith(path.join(root, 'tmp') + path.sep)) throw new Error('--output must be under this repository\'s ignored tmp/');
if (fs.existsSync(output)) throw new Error('Output already exists; choose a fresh --output to preserve earlier runs');
const baseline = values['compare-ref']
  ? execFileSync('git', ['rev-parse', '--verify', '--end-of-options', `${values['compare-ref']}^{commit}`], { cwd: root, encoding: 'utf8' }).trim()
  : undefined;
const production = path.join(root, 'roles/common/files/pi/extensions/managed-hooks.ts');
const definition = await loadDefinition();
const variants = [];
if (baseline) variants.push({ id: 'baseline', ref: baseline, description: (await loadDefinition(baseline)).description });
variants.push({ id: 'current', description: definition.description });
if (values.ablate) {
  const sections = definition.description.split('\n\n');
  if (sections.length !== 3) throw new Error('Expected three naming-description sections for leave-one-section-out ablations');
  variants.push(
    { id: 'without-call-threshold', description: sections.slice(1).join('\n\n') },
    { id: 'without-side-task-context', description: [sections[0], sections[2]].join('\n\n') },
    { id: 'without-name-construction', description: sections.slice(0, 2).join('\n\n') },
    { id: 'without-description', description: '' },
  );
}
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const report = { startedAt: new Date().toISOString(), model, thinking: 'low', trials,
  harborVersion: '0.24.0', piVersion: '1.0.2', productionSha256: hash(fs.readFileSync(production)),
  usageScope: 'All main-agent requests across five steps; automatic naming child usage is not captured by Harbor.',
  variants: [], results: [], errors: [] };
fs.mkdirSync(output, { recursive: true });
const save = () => fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
for (const variant of variants) {
  const task = path.join(output, 'tasks', variant.id, 'incidental-bug-report');
  fs.cpSync(path.join(root, 'evals/session-naming/tasks/incidental-bug-report'), task, { recursive: true, filter: source => !source.includes('__pycache__') });
  fs.mkdirSync(path.join(task, 'environment/project/tests'), { recursive: true });
  fs.copyFileSync(path.join(task, 'tests/restoration.rb'), path.join(task, 'environment/project/tests/restoration.rb'));
  fs.copyFileSync(production, path.join(task, 'environment/managed-hooks.ts'));
  fs.writeFileSync(path.join(task, 'environment/description.txt'), variant.description);
  fs.copyFileSync(path.join(root, 'roles/common/files/pi/AGENTS.md.d/00-base.md'), path.join(task, 'environment/AGENTS.md'));
  report.variants.push({ id: variant.id, ref: variant.ref, descriptionCharacters: variant.description.length,
    descriptionSha256: hash(variant.description), task });
}
save();
if (values['stage-only']) {
  console.log(`Staged ${variants.length} variants in ${output}; no model calls made`);
  process.exit(0);
}
const key = model.startsWith('openai/') ? 'OPENAI_API_KEY' : 'ANTHROPIC_API_KEY';
if (!process.env[key]) throw new Error(`Live Docker runs require ${key}; OAuth files are not copied`);
const env = {};
for (const name of ['PATH', 'LANG', 'TERM', 'DOCKER_HOST', key]) {
  if (process.env[name]) env[name] = process.env[name];
}
// Isolate host tool caches/state and never forward the parent session or unrelated credentials.
env.HOME = path.join(output, 'host-home');
env.XDG_CACHE_HOME = path.join(output, 'host-cache');
env.PYTHONDONTWRITEBYTECODE = '1';
env.TMPDIR = path.join(output, 'host-tmp');
env.DOCKER_CONFIG = path.join(output, 'docker-config');
for (const directory of [env.HOME, env.TMPDIR, env.DOCKER_CONFIG]) fs.mkdirSync(directory, { recursive: true });
if (!env.DOCKER_HOST) {
  env.DOCKER_HOST = execFileSync('docker', ['context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], { encoding: 'utf8' }).trim();
}
if (!env.DOCKER_HOST.startsWith('unix://')) throw new Error('Use a local Docker daemon socket, not a remote host');
// Keep installed Compose/Buildx available without copying registry credentials or Docker contexts.
const plugins = JSON.parse(execFileSync('docker', ['info', '--format', '{{json .ClientInfo.Plugins}}'], { encoding: 'utf8' }));
if (!plugins.some(plugin => plugin.Name === 'compose')) throw new Error('Docker Compose is required');
fs.writeFileSync(path.join(env.DOCKER_CONFIG, 'config.json'), JSON.stringify({ cliPluginsExtraDirs: [...new Set(plugins.map(plugin => path.dirname(plugin.Path)))] }));
execFileSync('docker', ['compose', 'version'], { env, stdio: 'ignore' });
const networkArgs = [];
if (values['docker-subnet']) {
  const overlay = path.join(output, 'docker-network.json');
  fs.writeFileSync(overlay, JSON.stringify({ networks: { default: { ipam: { config: [{ subnet: values['docker-subnet'] }] } } } }));
  networkArgs.push('--extra-docker-compose', overlay);
}
const harbor = path.resolve(values.harbor.includes('/') ? values.harbor : execFileSync('which', [values.harbor], { encoding: 'utf8' }).trim());
if (execFileSync(harbor, ['--version'], { env, encoding: 'utf8' }).trim() !== report.harborVersion) {
  throw new Error(`Install Harbor ${report.harborVersion}; the task and trace contracts are version-pinned`);
}
function run(args, log) {
  return new Promise((resolve, reject) => {
    const fd = fs.openSync(log, 'w');
    const child = spawn(harbor, args, { cwd: root, env, stdio: ['ignore', fd, fd] });
    fs.closeSync(fd);
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(new Error(`Harbor exited ${code}; inspect ${log}`)));
  });
}
function collect(variant) {
  const job = path.join(output, 'jobs', variant.id);
  const folders = fs.readdirSync(job, { withFileTypes: true }).filter(item => item.isDirectory() && fs.existsSync(path.join(job, item.name, 'result.json')));
  if (folders.length !== trials) throw new Error(`Expected ${trials} trial results in ${job}, found ${folders.length}`);
  for (const folder of folders) {
    const trial = path.join(job, folder.name);
    const result = JSON.parse(fs.readFileSync(path.join(trial, 'result.json')));
    if (result.exception_info || result.step_results?.some(step => step.exception_info)) throw new Error(`Harbor infrastructure error in ${trial}/result.json`);
    if (result.step_results?.length !== 5) throw new Error(`Incomplete workflow in ${trial}`);
    const steps = result.step_results.map(step => {
      const directory = path.join(trial, 'steps', step.step_name);
      const assessment = JSON.parse(fs.readFileSync(path.join(directory, 'verifier/assessment.json')));
      const reward = JSON.parse(fs.readFileSync(path.join(directory, 'verifier/reward.json')));
      return { step: step.step_name, ...assessment, reward, evidence: directory };
    });
    if (new Set(steps.map(step => step.sessionId)).size !== 1) throw new Error(`Session changed between steps in ${trial}`);
    const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
    for (const step of steps) for (const key of Object.keys(usage)) usage[key] += step.usage[key];
    report.results.push({ variant: variant.id, trial: folder.name, steps, mainAgentUsage: usage,
      namingPassed: steps.filter(step => step.naming).length, tasksPassed: steps.filter(step => step.task).length });
  }
}
for (const variant of report.variants) {
  console.log(`Running ${variant.id}: ${trials} five-step workflow(s)`);
  try {
    await run(['run', '--path', variant.task, '--agent', 'pi', '--model', model,
      '--agent-kwarg', 'version=1.0.2', '--agent-kwarg', 'thinking=low',
      '--agent-env', `PI_MANAGED_CHILD_MODEL=${model}`, '--agent-env', 'PI_TELEMETRY=0',
      '--agent-env', 'PI_SKIP_VERSION_CHECK=1', '--resume-trajectory',
      '--n-attempts', String(trials), '--n-concurrent', '1', ...networkArgs,
      '--job-name', variant.id, '--jobs-dir', path.join(output, 'jobs')], path.join(output, `${variant.id}.log`));
    collect(variant);
  } catch (error) {
    report.errors.push({ variant: variant.id, message: error.message });
    save();
    throw error;
  }
  save();
  console.log(`${variant.id}: ${report.results.filter(result => result.variant === variant.id).map(result => `${result.namingPassed}/5 naming, ${result.tasksPassed}/5 task steps`).join('; ')}`);
}
report.finishedAt = new Date().toISOString();
const currentResults = report.results.filter(result => result.variant === 'current');
report.currentPolicyPassed = currentResults.length === trials
  && currentResults.every(result => result.steps.every(step => step.naming && step.task));
save();
console.log(`Raw traces, native sessions, rewards, and report: ${output}`);
if (!report.currentPolicyPassed) {
  console.error('Current policy failed a naming or task check; baseline and ablation scores remain separate.');
  process.exitCode = 1;
}
