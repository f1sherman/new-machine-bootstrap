import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync, spawn } from 'node:child_process';
import { parseArgs } from 'node:util';
import { prepare, collect, collectTrial, findTrials, completedResult, root, readJSON } from './suites.mjs';
import { jobArguments } from './invocation.mjs';

const { values: options } = parseArgs({ options: {
  suite: { type: 'string' }, model: { type: 'string' }, trials: { type: 'string', default: '1' }, 'pi-version': { type: 'string' },
  cases: { type: 'string' }, conditions: { type: 'string' }, 'compare-ref': { type: 'string' }, ablate: { type: 'boolean' },
  mode: { type: 'string', default: 'regression' }, live: { type: 'boolean' }, replay: { type: 'string' },
  harbor: { type: 'string', default: 'tmp/harbor-venv/bin/harbor' }, python: { type: 'string', default: 'tmp/harbor-venv/bin/python' },
  'docker-subnet': { type: 'string' }, output: { type: 'string', default: 'tmp/harbor-evals' }, help: { type: 'boolean' },
} });
if (options.help) {
  console.log('Usage: node evals/harbor/run.mjs --suite command-guidance|session-naming\n  --model provider/model [--cases ids] [--conditions ids] [--trials 1]\n  [--live | --replay tmp/prior-run] [--mode regression|compare]\n  [--ablate] [--compare-ref ref] [--harbor path] [--python path]\n  [--pi-version X.Y.Z] [--docker-subnet CIDR] [--output tmp/fresh-run]\nDefault: stage only. --live makes paid calls. Replay makes no model calls.');
  process.exit(0);
}
if (!['regression', 'compare'].includes(options.mode)) throw Error('Unknown --mode');
if (options.live && options.replay) throw Error('--live and --replay are exclusive');
const tmp = path.join(fs.realpathSync(root), 'tmp');
fs.mkdirSync(tmp, { recursive: true });
if (fs.realpathSync(tmp) !== tmp) throw Error('tmp/ must not be a symlink');
function localPath(value) {
  const target = path.resolve(root, value);
  if (!target.startsWith(tmp + path.sep)) throw Error('Use paths under this checkout\'s ignored tmp/');
  let ancestor = target;
  while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
  const real = fs.realpathSync(ancestor);
  if (real !== tmp && !real.startsWith(tmp + path.sep)) throw Error('Output ancestor escapes tmp/');
  return target;
}
const output = localPath(options.output);
if (fs.existsSync(output)) throw Error('Use a fresh --output to preserve prior evidence');
const source = options.replay ? localPath(options.replay) : null;
const prior = source ? readJSON(path.join(source, 'manifest.json')) : null;
if (prior && (options.suite || options.model || options.cases || options.conditions || options.ablate || options['compare-ref'] || options['pi-version'])) throw Error('Replay uses its frozen manifest; do not override inputs');
if (prior && prior.suite !== 'command-guidance') throw Error('Replay is supported only for command-guidance');
const suite = prior?.suite ?? options.suite;
const model = prior?.model ?? options.model;
const trials = prior?.trials ?? Number(options.trials);
if (!/^(openai|anthropic)\/[A-Za-z0-9][A-Za-z0-9._-]*$/.test(model ?? '')) throw Error('Supply an explicit openai/model or anthropic/model');
if (!Number.isSafeInteger(trials) || trials < 1) throw Error('--trials must be a positive integer');
fs.mkdirSync(output, { recursive: true });
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function hashes(directory) {
  const result = {};
  function visit(folder) {
    for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
      const file = path.join(folder, entry.name);
      if (entry.isDirectory()) visit(file);
      else if (entry.isFile()) result[path.relative(directory, file)] = hash(fs.readFileSync(file));
      else throw Error('Staged inputs must be regular files/directories');
    }
  }
  visit(directory);
  return result;
}
let manifest;
if (source) {
  if (prior.schemaVersion !== 1) throw Error('Unsupported replay manifest');
  if (JSON.stringify(hashes(path.join(source, 'tasks'))) !== JSON.stringify(prior.inputHashes)) throw Error('Frozen staged inputs changed');
  fs.cpSync(path.join(source, 'tasks'), path.join(output, 'tasks'), { recursive: true });
  fs.cpSync(path.join(source, 'jobs'), path.join(output, 'jobs'), { recursive: true });
  manifest = prior;
} else {
  const piVersion = options['pi-version'] ?? execFileSync('ruby', ['-ryaml', '-e',
    'puts YAML.safe_load(File.read(ARGV[0])).fetch("tool_versions").fetch("runtimes").fetch("pi_coding_agent")',
    path.join(root, 'vars/tool_versions.yml')], { encoding: 'utf8' }).trim();
  if (!/^\d+\.\d+\.\d+$/.test(piVersion)) throw Error('Use an exact Pi release: --pi-version X.Y.Z');
  manifest = { schemaVersion: 1, model, trials, harborVersion: '0.24.0', piVersion,
    ...(await prepare(suite, { ...options, model, piVersion }, output)) };
  manifest.inputHashes = hashes(path.join(output, 'tasks'));
}
if (options.mode === 'regression' && !manifest.variants.some(variant => variant.primary)) throw Error('Regression mode requires the primary guidance/current condition');
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
const plannedUserTurns = trials * manifest.variants.length * manifest.cases.reduce((sum, item) => sum + (item.steps.length || 1), 0);
if (!Number.isSafeInteger(plannedUserTurns)) throw Error('Requested matrix is too large');
const report = { startedAt: new Date().toISOString(), suite, model, mode: options.mode, replayOf: source,
  plannedUserTurns, usageScope: 'Main-agent requests only; automatic naming-child usage and total billing are not captured.',
  results: [], errors: [] };
const save = () => fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
save();
console.log(`${suite}: ${manifest.cases.length} case(s), ${manifest.variants.length} condition(s), ${trials} trial(s), ${plannedUserTurns} planned user turns (not a billed-request count)`);
if (!options.live && !source) {
  console.log(`Staged ${output}; no Docker or model calls made. Use --live explicitly for paid execution.`);
  process.exit(0);
}
function execute(binary, args, log, env) {
  return new Promise((resolve, reject) => {
    const fd = fs.openSync(log, 'w');
    const child = spawn(binary, args, { cwd: root, env, stdio: ['ignore', fd, fd] });
    fs.closeSync(fd);
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve() : reject(Error(`Process exited ${code}; inspect ${log}`)));
  });
}
try {
  if (source) {
    for (const variant of manifest.variants) collect(manifest, source, variant);
    const python = path.resolve(root, options.python);
    const env = { PATH: process.env.PATH, PYTHONPATH: root, PYTHONDONTWRITEBYTECODE: '1' };
    for (const variant of manifest.variants) for (const trial of findTrials(path.join(output, 'jobs', variant.id))) {
      const item = completedResult(trial).task_name;
      await execute(python, ['-m', 'evals.harbor.command_verifier', '--task', path.join(output, 'tasks', variant.id, item), '--trial', trial], path.join(trial, 'replay.log'), env);
      report.results.push(collectTrial(manifest, output, variant, trial));
      save();
    }
  } else {
    const key = model.startsWith('openai/') ? 'OPENAI_API_KEY' : 'ANTHROPIC_API_KEY';
    if (!process.env[key]) throw Error(`Live runs require ${key}; host OAuth/config files are not copied`);
    const env = {};
    for (const name of ['PATH', 'LANG', 'TERM', 'DOCKER_HOST', key]) if (process.env[name]) env[name] = process.env[name];
    Object.assign(env, { HOME: path.join(output, 'host-home'), XDG_CACHE_HOME: path.join(output, 'host-cache'),
      TMPDIR: path.join(output, 'host-tmp'), DOCKER_CONFIG: path.join(output, 'docker-config'), PYTHONPATH: root, PYTHONDONTWRITEBYTECODE: '1' });
    for (const folder of [env.HOME, env.TMPDIR, env.DOCKER_CONFIG]) fs.mkdirSync(folder, { recursive: true });
    env.DOCKER_HOST ??= execFileSync('docker', ['context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], { encoding: 'utf8' }).trim();
    if (!env.DOCKER_HOST.startsWith('unix://')) throw Error('Use a local Docker daemon socket');
    const plugins = JSON.parse(execFileSync('docker', ['info', '--format', '{{json .ClientInfo.Plugins}}'], { encoding: 'utf8' }));
    if (!plugins.some(plugin => plugin.Name === 'compose')) throw Error('Docker Compose is required');
    fs.writeFileSync(path.join(env.DOCKER_CONFIG, 'config.json'), JSON.stringify({ cliPluginsExtraDirs: [...new Set(plugins.map(plugin => path.dirname(plugin.Path)))] }));
    execFileSync('docker', ['compose', 'version'], { env, stdio: 'ignore' });
    const harbor = options.harbor.includes('/') ? path.resolve(root, options.harbor) : execFileSync('which', [options.harbor], { encoding: 'utf8' }).trim();
    if (execFileSync(harbor, ['--version'], { env, encoding: 'utf8' }).trim() !== manifest.harborVersion) throw Error('Harbor version differs from pinned contract');
    const network = [];
    if (options['docker-subnet']) {
      const file = path.join(output, 'docker-network.json');
      fs.writeFileSync(file, JSON.stringify({ networks: { default: { ipam: { config: [{ subnet: options['docker-subnet'] }] } } } }));
      network.push('--extra-docker-compose', file);
    }
    // Rotate condition order across cases/trials rather than completing an entire
    // policy's corpus first. Each Harbor job owns one fresh trial/workflow.
    for (let attempt = 1; attempt <= trials; attempt++) for (const [index, item] of manifest.cases.entries()) {
      const offset = (index + attempt - 1) % manifest.variants.length;
      const ordered = [...manifest.variants.slice(offset), ...manifest.variants.slice(0, offset)];
      for (const variant of ordered) {
        const job = `${item.id}-${attempt}`;
        const args = jobArguments(manifest, output, variant, item, attempt, network);
        console.log(`Running ${variant.id}/${item.id}, trial ${attempt}/${trials}`);
        await execute(harbor, args, path.join(output, `${variant.id}-${job}.log`), env);
        const completed = findTrials(path.join(output, 'jobs', variant.id, job));
        if (completed.length !== 1) throw Error(`Expected one completed trial for ${variant.id}/${job}`);
        report.results.push(collectTrial(manifest, output, variant, completed[0]));
        save();
      }
    }
  }
  report.results = manifest.variants.flatMap(variant => collect(manifest, output, variant));
  const primary = report.results.filter(row => row.primary);
  report.currentPolicyPassed = primary.length > 0 && primary.every(row => row.passed);
  report.finishedAt = new Date().toISOString();
  save();
  console.log(`Current policy: ${report.currentPolicyPassed ? 'PASS' : 'FAIL'}; report ${output}/report.json`);
  if (options.mode === 'regression' && !report.currentPolicyPassed) process.exitCode = 1;
} catch (error) {
  report.errors.push({ message: error.message });
  save();
  console.error(error.message);
  process.exitCode = 1;
}
