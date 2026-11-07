#!/usr/bin/env node
// Generates tool-free responses on the host; the existing grader executes them in its macOS sandbox.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const flags = process.argv.slice(2);
const options = {};
for (let i = 0; i < flags.length; i++) {
  const flag = flags[i];
  if (flag === '--live') options.live = true;
  else if (['--output', '--replay', '--regrade', '--model'].includes(flag)) {
    if (!flags[i + 1] || flags[i + 1].startsWith('--')) throw Error('Missing value for ' + flag);
    options[flag.slice(2)] = flags[++i];
  } else throw Error('Unknown option: ' + flag);
}
if (!options.output || [options.live, options.replay, options.regrade].filter(Boolean).length > 1) throw Error('Provide --output and at most one execution mode');
if ((options.replay || options.regrade) && options.model) throw Error('Replay and regrade do not accept a model override');
const tmp = path.join(root, 'tmp');
fs.mkdirSync(tmp, {recursive: true, mode: 0o700});
if (fs.realpathSync(tmp) !== tmp) throw Error('tmp must not be a symlink');
function local(value) {
  const result = path.resolve(root, value);
  if (!result.startsWith(tmp + path.sep)) throw Error('Use paths under this checkout’s tmp directory');
  let ancestor = result;
  while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
  const real = fs.realpathSync(ancestor);
  if (real !== tmp && !real.startsWith(tmp + path.sep)) throw Error('Path escapes tmp');
  return result;
}
const output = local(options.output);
if (fs.existsSync(output)) throw Error('Use a fresh output directory');
fs.mkdirSync(output, {recursive: true, mode: 0o700});
const save = (name, value) => fs.writeFileSync(path.join(output, name), JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const execute = promisify(execFile);
const grader = path.join(here, 'grader.rb');
const casesFile = path.join(here, 'cases.json');
const guidanceFile = path.join(here, 'variants/guidance.md');
const deployedFile = path.join(root, 'roles/common/files/pi/AGENTS.md.d/00-base.md');
const source = (options.replay || options.regrade) && local(options.replay || options.regrade);
let manifest;
if (source) {
  const bytes = fs.readFileSync(path.join(source, 'manifest.json'));
  const receipt = JSON.parse(fs.readFileSync(path.join(source, 'receipts.json')));
  if (hash(bytes) !== receipt.manifest) throw Error('Manifest receipt mismatch');
  manifest = JSON.parse(bytes);
  const graderHash = hash(fs.readFileSync(grader));
  if (options.replay && graderHash !== manifest.sources.grader) throw Error('Grader changed; preserve the original and regrade explicitly');
  if (options.regrade) {
    manifest.derivation = {sourceManifestSha256: hash(bytes), previousGraderSha256: manifest.sources.grader,
      reason: 'Regrade the same captured responses with the current grader; no model calls.'};
    manifest.sources = {...manifest.sources, grader: graderHash, regradeRunner: hash(fs.readFileSync(import.meta.filename))};
  }
} else {
  const guidance = fs.readFileSync(guidanceFile, 'utf8');
  const deployed = fs.readFileSync(deployedFile, 'utf8');
  if (!deployed.includes(guidance.trim())) throw Error('Terminal guidance differs from the managed Pi source');
  const removals = {
    line_width: 'For user copy-paste commands, every line—including variable assignments—must fit 80 characters. ',
    heredocs: 'No heredocs or visual wrapping. ',
    argument_boundaries: 'Put `\\` continuations between complete arguments only, never inside paths, URLs, quoted strings, or `--opt=value`/`key=value`. ',
    variable_names: 'Store arguments over ~60 characters in variables named f or url (not Zsh’s path); expand them quoted (`"$f"`). ',
    long_assignments: 'If an assignment exceeds 80 characters, construct its value with `printf` or successive short assignments. ',
    literal_newlines: 'Literal quoted newlines are allowed only where jq/awk treats them as program whitespace, never inside paths or data values. ',
    final_check: 'Before sending, remove `\\`-newlines mentally, retain indentation, and verify intact arguments.\n\n',
    example: 'Build long values across short assignments:\n```bash\nf="$HOME/.config/rendered"\nf="$f/production/application/settings.yaml"\ncat "$f"\n```\n',
  };
  const conditions = {guidance, none: ''};
  for (const [name, text] of Object.entries(removals)) {
    if (guidance.split(text).length !== 2) throw Error('Production component changed: ' + name);
    conditions['without_' + name] = guidance.replace(text, '');
  }
  const cases = JSON.parse(fs.readFileSync(casesFile));
  const matrix = cases.flatMap((item, i) => {
    const names = Object.keys(conditions);
    return names.map((_, j) => ({case: item.id, condition: names[(i + j) % names.length], file: `${item.id}-${names[(i + j) % names.length]}.json`}));
  });
  const piVersion = (await execute('pi', ['--version'])).stdout.trim();
  manifest = {version: 1, model: {provider: 'openai-codex', id: options.model || 'gpt-6.1-terra', thinking: 'medium'}, piVersion,
    common: 'You are a coding assistant. Give terminal commands for a user to copy and paste.\n\n',
    cases, conditions, removals, matrix, parallel: 3,
    criteria: 'Keep all trials; report format and functional failures separately. Compare token use only on matching successful cases. Any infrastructure failure makes the study incomplete. One sample per case and redundant rules cannot establish general necessity.',
    scope: 'Host Pi CLI without tools, sessions, context files, extensions or skills; generated commands run only in the existing macOS sandbox grader. This is an excerpt study, not a full session.',
    sources: {runner: hash(fs.readFileSync(import.meta.filename)), grader: hash(fs.readFileSync(grader)), cases: hash(fs.readFileSync(casesFile)), guidance: hash(fs.readFileSync(guidanceFile)), deployed: hash(deployed)}};
}
const caseIds = manifest.cases.map(item => item.id);
const conditionIds = Object.keys(manifest.conditions);
const trialIds = new Set();
const safeId = value => typeof value === 'string' && /^[a-z0-9][a-z0-9_-]{0,63}$/.test(value);
if (!caseIds.length || new Set(caseIds).size !== caseIds.length || !conditionIds.length ||
    !caseIds.every(safeId) || !conditionIds.every(safeId) ||
    !Number.isInteger(manifest.parallel) || manifest.parallel < 1 || manifest.parallel > 3 ||
    manifest.matrix.length !== caseIds.length * conditionIds.length) throw Error('Invalid trial matrix');
for (const row of manifest.matrix) {
  const key = `${row.case}:${row.condition}`;
  if (!caseIds.includes(row.case) || !conditionIds.includes(row.condition) || trialIds.has(key) ||
      row.file !== `${row.case}-${row.condition}.json`) throw Error('Invalid or duplicate trial');
  trialIds.add(key);
}
save('manifest.json', manifest);
if (!options.live && !source) { console.log(`Staged ${manifest.matrix.length} trials; no model calls.`); process.exit(0); }
const receipt = {manifest: hash(fs.readFileSync(path.join(output, 'manifest.json'))), trials: {}};
if (source) {
  const original = JSON.parse(fs.readFileSync(path.join(source, 'receipts.json')));
  for (const row of manifest.matrix) {
    const bytes = fs.readFileSync(path.join(source, row.file));
    if (hash(bytes) !== original.trials[row.file]) throw Error('Trial receipt mismatch: ' + row.file);
  }
}
const frozenGrader = path.join(output, 'grader.rb');
fs.copyFileSync(grader, frozenGrader);
if (hash(fs.readFileSync(frozenGrader)) !== manifest.sources.grader) throw Error('Frozen grader differs from manifest');
const workdir = path.join(output, 'cwd');
fs.mkdirSync(workdir, {mode: 0o700});
const graderEnv = Object.fromEntries(['PATH', 'TMPDIR'].filter(k => process.env[k]).map(k => [k, process.env[k]]));
graderEnv.LANG = 'en_US.UTF-8';
graderEnv.COMMAND_GUIDANCE_EVAL_SCRATCH = path.join(output, 'sandbox');
let next = 0;
const results = [];
async function worker() {
  while (next < manifest.matrix.length) {
    const row = manifest.matrix[next++];
    const item = manifest.cases.find(c => c.id === row.case);
    const prompt = item.prompt + '\nReturn only one shell code block with all required commands. Do not execute anything.';
    const system = manifest.common + manifest.conditions[row.condition];
    const settings = {provider: manifest.model.provider, model: manifest.model.id, thinking: manifest.model.thinking, system_prompt: system, prompt};
    let record = {...row, status: 'incomplete'};
    try {
      let events;
      if (source) {
        const old = JSON.parse(fs.readFileSync(path.join(source, row.file)));
        if (old.status !== 'complete' || !old.events) throw Error('Prior generation is incomplete');
        events = old.events;
        if (options.regrade) record.previous_assessment = old.assessment;
      } else {
        const args = ['--offline', '--provider', settings.provider, '--model', settings.model, '--thinking', settings.thinking,
          '--no-session', '--no-context-files', '--no-tools', '--no-extensions', '--no-mcp', '--no-skills',
          '--no-prompt-templates', '--no-themes', '--system-prompt', system, '--mode', 'json', '--print', prompt];
        const child = execute('pi', args, {cwd: workdir, timeout: 180000, maxBuffer: 8 * 1024 * 1024});
        child.child.stdin.end();
        const result = await child;
        events = result.stdout;
        record.stderr = result.stderr;
      }
      record.events = events;
      const request = path.join(output, row.file + '.request');
      fs.writeFileSync(request, JSON.stringify({events, settings, test_case: item}), {mode: 0o600});
      if (hash(fs.readFileSync(frozenGrader)) !== manifest.sources.grader) throw Error('Frozen grader changed');
      const response = await execute('ruby', [frozenGrader, request], {cwd: root, env: graderEnv, timeout: 30000, maxBuffer: 8 * 1024 * 1024});
      const assessment = JSON.parse(response.stdout);
      if (assessment.infrastructure_error || typeof assessment.grade?.pass !== 'boolean') throw Error(assessment.infrastructure_error || 'Invalid grader output');
      if (assessment.provider !== settings.provider || assessment.model !== settings.model) throw Error('Response model differs from frozen settings');
      record = {...record, status: 'complete', assessment};
    } catch (error) {
      record.error = error.message;
      record.stdout ??= error.stdout;
      record.stderr ??= error.stderr;
    }
    save(row.file, record);
    receipt.trials[row.file] = hash(fs.readFileSync(path.join(output, row.file)));
    save('receipts.json', receipt);
    results.push({case: row.case, condition: row.condition, status: record.status, pass: record.assessment?.grade?.pass ?? null, error: record.error});
    save('report.json', results);
    console.log(row.case, row.condition, record.status, record.assessment?.grade?.pass ?? '');
  }
}
save('receipts.json', receipt);
await Promise.all(Array.from({length: manifest.parallel}, worker));
if (results.length !== manifest.matrix.length || results.some(r => r.status !== 'complete' || (r.condition === 'guidance' && !r.pass))) process.exitCode = 1;
