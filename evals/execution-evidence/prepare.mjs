import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';

const root = new URL('../../', import.meta.url);
const skillPath = 'roles/common/files/config/skills/common/eval-design/SKILL.md';
const baselineCommit = '6053232bf1ac42fbac400903e553ca0df97f5ef6';
const strip = source => source.replace(/^---\n[\s\S]*?\n---\n/, '').trim();
const source = fs.readFileSync(new URL(skillPath, root), 'utf8');
const body = strip(source);
const previous = strip(execFileSync('git', ['show', `${baselineCommit}:${skillPath}`],
  {cwd: root, encoding: 'utf8'}));
const section = body.split('## Exercise the real workflow\n\n')[1]?.split('\n\n## 4.')[0];
assert.ok(section, 'Review policy boundaries after changing the skill');
const components = section.split('\n\n');
assert.equal(components.length, 3, 'Review component boundaries after changing the skill');
const conditions = {empty: '', historical: previous, full: body};
for (const [index, name] of ['task', 'observation', 'boundary'].entries()) {
  conditions[`without-${name}`] = body.replace(components[index], '');
}
const cases = JSON.parse(fs.readFileSync(new URL('../checked-in-evals/cases.json', import.meta.url)));
const keys = Object.keys(conditions);
const experiment = {
  version: 1,
  id: 'execution-evidence',
  scope: 'Tool-enabled Git repository tasks using the checked-in-evals executor and verifier. Standalone skill bodies; no ambient policy. Reused diagnostic cases, not unseen validation. No live publication.',
  source: {path: skillPath, sha256: crypto.createHash('sha256').update(source).digest('hex'), baselineCommit},
  systemPrefix: 'You are a coding assistant working in an isolated local repository. Complete the user task using the available shell tool.\n\n',
  model: {provider: 'openai-codex', id: 'gpt-6.1-sol', reasoning: 'medium', maxTokens: 4000},
  conditions, cases,
  order: cases.flatMap((task, index) => [...keys.slice(index), ...keys.slice(0, index)]
    .map(condition => ({case: task.id, condition}))),
  grading: 'Use checked-in-evals/workflow/fixture.mjs to verify actual staged code, faithful current-source evidence, independently runnable documented commands, privacy, and broken-production detection. Terminal prose is not a grade. Keep incomplete execution separate.'
};
fs.writeFileSync(new URL('./experiment.json', import.meta.url), JSON.stringify(experiment, null, 2) + '\n');
console.log('Prepared execution-evidence from the current production skill.');
