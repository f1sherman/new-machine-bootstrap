#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const [stage, destination, selected] = process.argv.slice(2);
assert.ok(['development', 'confirmation', 'combined-screen', 'combined-check'].includes(stage));
const combined = stage.startsWith('combined-');
const study = combined ? JSON.parse(fs.readFileSync(path.join(here, 'combinations.json'))) : null;
assert.ok(destination, 'Provide a fresh output directory');
const output = path.resolve(destination);
assert.ok(!fs.existsSync(output), 'Never overwrite a run');
fs.mkdirSync(output, {recursive: true});
const save = (name, data) => fs.writeFileSync(path.join(output, name), JSON.stringify(data, null, 2) + '\n');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const baseline = study?.original ?? JSON.parse(fs.readFileSync(path.join(here, 'results.json'))).stages.dev.baseline;
assert.ok(baseline.startsWith('use ASD-STE100'));
const components = {
  suggested: ['Use plain English.', 'Explain the practical meaning first.', 'Define technical terms when needed.'],
  compact: ['Use plain English.', 'Lead with what it means for Brian.', 'Explain necessary jargon.'],
  concrete: ['Use everyday words in every reply.', 'Start with what the result means for Brian and what he should do next.', 'Explain necessary technical terms where they first appear, using a concrete example when useful.']
};
const full = name => baseline + ' ' + components[name].join(' ');
let conditions = {empty: '', baseline, ...Object.fromEntries(Object.keys(components).map(name => [name, full(name)]))};
if (stage === 'confirmation') {
  assert.ok(Object.hasOwn(components, selected), 'Name the frozen selected variant');
  conditions = {baseline, [selected]: full(selected)};
  for (let i = 0; i < 3; i++) conditions[`without_${i}`] = baseline + ' ' + components[selected].filter((_, j) => i !== j).join(' ');
}
if (combined) {
  const entries = Object.entries(study.components);
  const current = entries.map(([, text]) => text).join(' ');
  if (stage === 'combined-screen') {
    conditions = {empty: '', original: baseline, current};
    for (const [id] of entries) conditions[`without_${id}`] = entries.filter(([key]) => key !== id).map(([, text]) => text).join(' ');
    for (const [id, parts] of Object.entries(study.rewrites)) conditions[id] = parts.join(' ');
  } else {
    assert.ok(Object.hasOwn(study.rewrites, selected), 'Name the frozen selected rewrite');
    const parts = study.rewrites[selected];
    conditions = {current, [selected]: parts.join(' ')};
    for (let i = 0; i < parts.length; i++) conditions[`without_${i}`] = parts.filter((_, j) => i !== j).join(' ');
  }
}
const cases = study?.cases ?? JSON.parse(fs.readFileSync(path.join(here, 'cases.json')));
const names = Object.keys(conditions);
const matrix = cases.filter(c => ['confirmation', 'combined-check'].includes(stage) || c.split === 'development').flatMap((c, i) =>
  names.map((_, j) => ({case: c.id, condition: names[(i + j) % names.length], file: `${c.id}-${names[(i + j) % names.length]}.json`})));
const execute = promisify(execFile);
const manifest = {
  stage, selected, baseline, components: study?.components ?? components, rewrites: study?.rewrites, conditions, cases, matrix,
  common: 'You are a helpful assistant. Answer the user request.',
  model: {provider: 'openai-codex', id: 'gpt-6.1-sol', thinking: 'off'},
  piVersion: (await execute('pi', ['--version'])).stdout.trim(),
  sources: Object.fromEntries(['run.mjs', ...(combined ? ['combinations.json', 'combination-grading.json', 'COMBINATIONS.md'] : ['cases.json', 'README.md'])].map(f => [f, hash(fs.readFileSync(path.join(here, f)))]))
};
save('manifest.json', manifest);
const receipts = {manifest: hash(fs.readFileSync(path.join(output, 'manifest.json'))), trials: {}};
save('receipts.json', receipts);
let next = 0;
async function worker() {
  while (next < matrix.length) {
    const row = matrix[next++];
    const c = cases.find(c => c.id === row.case);
    const args = ['--offline', '--provider', manifest.model.provider, '--model', manifest.model.id,
      '--thinking', manifest.model.thinking, '--no-session', '--no-context-files', '--no-tools',
      '--no-extensions', '--no-mcp', '--no-skills', '--no-prompt-templates', '--no-themes',
      '--system-prompt', manifest.common + '\n' + conditions[row.condition], '--mode', 'json', '--print', c.request];
    const record = {...row, status: 'incomplete', args};
    try {
      const running = execute('pi', args, {timeout: 180000, maxBuffer: 8 * 1024 * 1024});
      running.child.stdin.end();
      Object.assign(record, await running);
      const responses = record.stdout.trim().split('\n').map(line => JSON.parse(line))
        .filter(e => e.type === 'message_end' && e.message?.role === 'assistant').map(e => e.message);
      assert.equal(responses.length, 1);
      const response = responses[0];
      assert.ok(!['error', 'aborted', 'length'].includes(response.stopReason), response.errorMessage || response.stopReason);
      record.response = response;
      record.answer = response.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
      assert.ok(record.answer.trim());
      record.status = 'complete';
    } catch (error) {
      record.error = error.message;
      record.stdout ??= error.stdout;
      record.stderr ??= error.stderr;
    }
    save(row.file, record);
    receipts.trials[row.file] = hash(fs.readFileSync(path.join(output, row.file)));
    save('receipts.json', receipts);
    console.log(row.case, row.condition, record.status, JSON.stringify(record.response?.usage));
  }
}
await Promise.all(Array.from({length: 3}, worker));
const records = matrix.map(row => JSON.parse(fs.readFileSync(path.join(output, row.file))));
const packet = {
  rubric: {
    accuracy: '0: incorrect advice, fabricated result, or material omission. 1: mostly correct but one required fact missing or ambiguous. 2: all required facts intact and no invented claim.',
    everyday: '0: abstract or jargon-heavy explanation. 1: mostly readable but some needless jargon or compressed technical labels. 2: everyday language throughout; exact identifiers and necessary defined terms are fine.',
    meaning: '0: starts with mechanics, labels, or a numeric dump before explaining the point. 1: main meaning is present but delayed or incomplete. 2: opens with a clear practical conclusion grounded in the facts.',
    terms: '0: necessary unfamiliar terms left unexplained or badly defined. 1: partial or awkward explanations. 2: terms replaced with clear language or explained where used. Do not reward gratuitous definitions or penalize avoiding jargon.',
    instructions: 'Judge each answer independently. Do not reward shortness, formatting, or resemblance to a reference answer. Return JSON rows with label, accuracy, everyday, meaning, terms, and a short evidence reason. Do not infer condition identities. Required facts are a completeness checklist, not mandatory wording.',
    ...(combined ? JSON.parse(fs.readFileSync(path.join(here, 'combination-grading.json'))).rubric : {})
  },
  rows: records.map((r, i) => ({label: `R${String(i + 1).padStart(2, '0')}`, case: r.case,
    request: cases.find(c => c.id === r.case).request, required: cases.find(c => c.id === r.case).required,
    ...(combined ? {relevance: cases.find(c => c.id === r.case).relevance} : {}), answer: r.answer}))
};
packet.rows.sort((a, b) => hash(a.label + 'plain-language').localeCompare(hash(b.label + 'plain-language')));
save('packet.json', packet);
save('labels.json', Object.fromEntries(records.map((r, i) => [`R${String(i + 1).padStart(2, '0')}`, {case: r.case, condition: r.condition, file: r.file}])));
process.exitCode = records.some(r => r.status !== 'complete') ? 1 : 0;
