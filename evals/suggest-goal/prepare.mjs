import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';

const root = new URL('../../', import.meta.url);
const skillPath = 'roles/common/files/config/skills/pi/z-suggest-goal/SKILL.md';
const source = fs.readFileSync(new URL(skillPath, root), 'utf8');
const body = source.replace(/^---\n[\s\S]*?\n---\n/, '').trim();
const blocks = body.split(/\n\n/);
const paragraphs = blocks.filter(block => !block.startsWith('#'));
assert.equal(paragraphs.length, 5, 'Review ablation boundaries after changing the skill');
const names = ['guard', 'selection', 'drafting', 'progress', 'format'];
const baselineCommit = '2ac73ced27e931d9e03558615970f61ad713e5cf';
const historical = execFileSync('git', ['show', `${baselineCommit}:${skillPath}`],
  {cwd: root, encoding: 'utf8'}).replace(/^---\n[\s\S]*?\n---\n/, '').trim();
const conditions = {empty: '', historical, full: body};
for (const [index, name] of names.entries()) {
  conditions[`without-${name}`] = blocks.filter(block => block !== paragraphs[index]).join('\n\n');
}
const cases = JSON.parse(fs.readFileSync(new URL('./cases.json', import.meta.url)));
const keys = Object.keys(conditions);
const experiment = {
  version: 1,
  id: 'suggest-goal',
  scope: 'Tool-free skill-body study. Fresh calls, no ambient project instructions. Manual semantic grading.',
  source: {path: skillPath, sha256: crypto.createHash('sha256').update(source).digest('hex'), baselineCommit},
  systemPrefix: 'You are a helpful assistant. Respond to the user using the supplied session context.\n\n',
  model: {provider: 'openai-codex', id: 'gpt-6.1-sol', reasoning: 'medium', maxTokens: 3000},
  conditions,
  cases,
  order: cases.flatMap((task, index) => [...keys.slice(index), ...keys.slice(0, index)]
    .map(condition => ({case: task.id, condition}))),
  grading: 'Score each criterion 0 for missing/incorrect, 1 for partial, 2 for complete. Pass requires every criterion to score 2. A completed call is not a passing answer. No tools are available, so live goal-tool safety is untested.'
};
fs.writeFileSync(new URL('../eval-design/experiments/suggest-goal.json', import.meta.url),
  JSON.stringify(experiment, null, 2) + '\n');
console.log('Prepared suggest-goal from the current skill; review the fixture diff before running.');
