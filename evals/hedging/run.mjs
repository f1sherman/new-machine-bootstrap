#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import assert from 'node:assert/strict';
import {system as judgeSystem, parse, calibration} from './grader.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const options = {};
for (let i = 2; i < process.argv.length; i++) {
  const key = process.argv[i];
  if (key === '--live') options.live = true;
  else if (['--output', '--split', '--replay', '--regrade', '--pi'].includes(key)) {
    const value = process.argv[++i];
    if (!value || value.startsWith('--')) throw new Error('Missing value: ' + key);
    options[key.slice(2)] = value;
  } else throw new Error('Unknown option: ' + key);
}
if (!options.output) throw new Error('--output is required');
const output = path.resolve(options.output);
if (fs.existsSync(output)) throw new Error('Use a fresh output directory');
fs.mkdirSync(output, {recursive: true});
const save = (name, value) => fs.writeFileSync(path.join(output, name), JSON.stringify(value, null, 2));
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const sum = (rows, key) => rows.reduce((n, r) => n + (r.response?.usage?.[key] || 0), 0);
function summarize(records) {
  return Object.fromEntries([...new Set(records.map(r => r.condition))].map(condition => {
    const rows = records.filter(r => r.condition === condition);
    return [condition, {
      completed: rows.filter(r => r.status === 'complete').length,
      infrastructure_errors: rows.filter(r => r.status !== 'complete').length,
      useful: rows.filter(r => r.assessment?.useful).length,
      redundant_caveats: rows.filter(r => r.assessment?.redundant_caveat).length,
      passed: rows.filter(r => r.assessment?.pass).length,
      input_tokens: sum(rows, 'input'), output_tokens: sum(rows, 'output')
    }];
  }));
}
if (options.replay) {
  assert.deepEqual(Object.keys(options).sort(), ['output', 'replay']);
  const source = path.resolve(options.replay);
  const receipts = JSON.parse(fs.readFileSync(path.join(source, 'receipts.json')));
  const manifestBytes = fs.readFileSync(path.join(source, 'manifest.json'));
  assert.equal(hash(manifestBytes), receipts.manifest);
  const manifest = JSON.parse(manifestBytes);
  const records = manifest.matrix.map(row => {
    const bytes = fs.readFileSync(path.join(source, row.file));
    assert.equal(hash(bytes), receipts.trials[row.file]);
    const r = JSON.parse(bytes);
    if (r.status === 'complete') assert.deepEqual(parse(r.judge_text), r.assessment);
    return r;
  });
  save('report.json', {records, summary: summarize(records)});
  console.log(JSON.stringify(summarize(records), null, 2));
  process.exit(records.some(r => r.status !== 'complete' || (r.condition === 'candidate' && !r.assessment.pass)) ? 1 : 0);
}
let previous;
if (options.regrade) {
  const dir = path.resolve(options.regrade);
  const bytes = fs.readFileSync(path.join(dir, 'manifest.json'));
  const receipts = JSON.parse(fs.readFileSync(path.join(dir, 'receipts.json')));
  assert.equal(hash(bytes), receipts.manifest);
  const frozen = JSON.parse(bytes);
  const records = Object.fromEntries(frozen.matrix.map(row => {
    const raw = fs.readFileSync(path.join(dir, row.file));
    assert.equal(hash(raw), receipts.trials[row.file]);
    const r = JSON.parse(raw);
    assert.ok(r.response && r.answer, 'Regrade requires a captured generation');
    return [row.file, r];
  }));
  previous = {dir, manifest: frozen, records, manifestSha256: hash(bytes)};
}
const split = previous?.manifest.split || options.split || 'development';
if (!['development', 'validation'].includes(split)) throw new Error('Invalid split');
const cases = JSON.parse(fs.readFileSync(path.join(here, 'cases.json')));
const source = fs.readFileSync(path.join(here, '../../roles/common/files/pi/AGENTS.md.d/00-base.md'), 'utf8');
const claude = fs.readFileSync(path.join(here, '../../roles/common/files/claude/CLAUDE.md.d/00-base.md'), 'utf8');
const opening = source.split('\n')[0];
assert.equal(opening, claude.split('\n')[0], 'Writing guidance differs between harnesses');
const baseline = opening.split('Writing style: ')[1].split(' State the point directly.')[0];
assert.ok(baseline && baseline !== opening);
const direct = 'State the point directly.';
const material = 'Keep uncertainty, limits, and risks that affect factual accuracy, a decision, or the next action.';
const context = 'Before sending, delete caveats that repeat context, deny claims you did not make, or add no useful information. Describe a proposed benefit without appending that it is unmeasured or not guaranteed.';
const rule = `${direct} ${context} ${material}`;
assert.equal(opening.split('Writing style: ')[1], `${baseline} ${rule}`, 'Update the ablations for changed production guidance');
const conditions = {
  empty: '', baseline, candidate: `${baseline} ${rule}`,
  no_direct: `${baseline} ${context} ${material}`,
  no_material: `${baseline} ${direct} ${context}`,
  no_context: `${baseline} ${direct} ${material}`
};
const names = split === 'validation' ? ['baseline', 'candidate'] : Object.keys(conditions);
const matrix = [];
for (const [i, c] of cases.filter(c => c.split === split).entries()) {
  for (let j = 0; j < names.length; j++) {
    const condition = names[(i + j) % names.length];
    matrix.push({case: c.id, condition, file: `${c.id}-${condition}.json`});
  }
}
const manifest = {
  version: 1, split, cases, conditions, matrix,
  scope: 'Standalone production writing excerpt, not full deployed instructions. One sample per task and condition. Validation tasks are excluded from development.',
  model: {provider: 'openai-codex', id: 'gpt-6.1-sol', reasoning: 'off'},
  runtime: {pi: options.pi || 'pi', version: (await promisify(execFile)(options.pi || 'pi', ['--version'])).stdout.trim()},
  common: 'You are a helpful assistant. Answer the user request.',
  grader: {system: judgeSystem, calibration},
  sources: Object.fromEntries(['run.mjs', 'grader.mjs', 'cases.json'].map(f => [f, hash(fs.readFileSync(path.join(here, f)))])),
  criteria: 'Candidate must preserve required information in every case and contain no redundant caveat. A useful behavioral improvement requires at least one paired baseline failure corrected by the candidate. Token reduction alone does not establish the intended effect. All requested calls and grader calibrations must finish. Null ablations do not prove components unnecessary.'
};
if (previous) {
  manifest.conditions = previous.manifest.conditions;
  manifest.matrix = previous.manifest.matrix;
  matrix.splice(0, matrix.length, ...previous.manifest.matrix);
  manifest.derivation = {source: previous.dir, manifestSha256: previous.manifestSha256,
    change: 'Regrade the same captured generations with the corrected material-safeguard criterion; never resample.'};
}
save('manifest.json', manifest);
if (!options.live) {console.log(`Staged ${matrix.length} trials; no model calls.`); process.exit(0);}
const execute = promisify(execFile);
const text = response => response.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
let callId = 0;
async function call(systemPrompt, request) {
  const id = ++callId;
  const args = ['--offline', '--provider', manifest.model.provider, '--model', manifest.model.id,
    '--thinking', manifest.model.reasoning, '--no-session', '--no-context-files',
    '--no-tools', '--no-extensions', '--no-mcp', '--no-skills',
    '--no-prompt-templates', '--no-themes', '--system-prompt', systemPrompt,
    '--mode', 'json', '--print', request];
  let stream;
  try {
    const running = execute(manifest.runtime.pi, args, {timeout: 120000, maxBuffer: 8 * 1024 * 1024});
    running.child.stdin.end();
    stream = await running;
  } catch (error) {
    save(`call-${id}.json`, {args, stdout: error.stdout, stderr: error.stderr, error: error.message});
    throw error;
  }
  save(`call-${id}.json`, {args, ...stream});
  const messages = stream.stdout.trim().split('\n').map(line => JSON.parse(line))
    .filter(event => event.type === 'message_end' && event.message?.role === 'assistant')
    .map(event => event.message);
  assert.equal(messages.length, 1, 'Expected one assistant response');
  const response = messages[0];
  if (['error', 'aborted', 'length'].includes(response.stopReason)) {
    throw Object.assign(new Error('Incomplete provider response: ' + response.stopReason), {response});
  }
  return response;
}
async function judge(c, answer) {
  const response = await call(judgeSystem, JSON.stringify({request: c.request, required: c.required, redundant: c.redundant, answer}));
  return {response, text: text(response), assessment: parse(text(response))};
}
// Calibrate the same semantic grader used for every generated response.
for (const [i, sample] of calibration.entries()) {
  const result = await judge(cases.find(c => c.id === sample.case), sample.answer);
  save(`calibration-${i}.json`, {sample, ...result});
  assert.equal(result.assessment.useful, sample.useful);
  assert.equal(result.assessment.redundant_caveat, sample.redundant_caveat);
}
const receipts = {manifest: hash(fs.readFileSync(path.join(output, 'manifest.json'))), trials: {}};
save('receipts.json', receipts);
const records = [];
// Fixed, bounded concurrency; all work remains owned by this foreground run.
let next = 0;
async function worker() {
  while (next < matrix.length) {
    const row = matrix[next++], c = cases.find(c => c.id === row.case);
    const record = {...row, status: 'complete'};
    try {
      record.response = previous ? previous.records[row.file].response
        : await call(manifest.common + '\n' + conditions[row.condition], c.request);
      record.answer = text(record.response);
      save(row.file, record);
      const result = await judge(c, record.answer);
      Object.assign(record, {judge: result.response, judge_text: result.text, assessment: result.assessment});
    } catch (error) {
      Object.assign(record, {status: 'infrastructure_error', error: error.message, failed_response: error.response});
    }
    save(row.file, record);
    receipts.trials[row.file] = hash(fs.readFileSync(path.join(output, row.file)));
    save('receipts.json', receipts);
    records.push(record);
    save('report.json', {records, summary: summarize(records)});
    console.log(`${row.case} ${row.condition}: ${record.assessment?.pass ?? record.status}`);
  }
}
await Promise.all(Array.from({length: 3}, worker));
console.log(JSON.stringify(summarize(records), null, 2));
process.exitCode = records.some(r => r.status !== 'complete' || (r.condition === 'candidate' && !r.assessment.pass)) ? 1 : 0;
