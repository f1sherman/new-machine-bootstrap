import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';

const root = new URL('../../', import.meta.url);
const skillPath = 'roles/common/files/config/skills/common/eval-design/SKILL.md';
const baselineCommit = '57c3a01d008ebdf2a43004d4a91b4fefa69efe7f';
const historical = execFileSync('git', ['show', `${baselineCommit}:${skillPath}`],
  {cwd: root, encoding: 'utf8'});
const source = fs.readFileSync(new URL(skillPath, root), 'utf8');
const body = source.replace(/^---\n[\s\S]*?\n---\n/, '').trim();
const section = body.split('## 6. Check in rerunnable evals\n\n')[1]?.split('\n\n## 7.')[0];
assert.ok(section, 'Review the policy section boundaries after changing the skill');
const components = section.split('\n\n');
assert.equal(components.length, 4, 'Review ablation boundaries after changing the skill');
const conditions = {
  empty: '',
  historical: historical.replace(/^---\n[\s\S]*?\n---\n/, '').trim(),
  full: body
};
for (const [index, name] of ['fixtures', 'evidence', 'privacy', 'recheck'].entries()) {
  conditions[`without-${name}`] = body.replace(components[index], '');
}
const cases = JSON.parse(fs.readFileSync(new URL('./cases.json', import.meta.url)));
const keys = Object.keys(conditions);
const experiment = {
  version: 1,
  id: 'checked-in-evals',
  scope: 'Tool-enabled local Git workflows. Standalone eval-design bodies without ambient policy. Grades actual staged artifacts, clean-index execution, source mutation, and synthetic private-marker exclusion. No live forge publication.',
  source: {path: skillPath, sha256: crypto.createHash('sha256').update(source).digest('hex'), baselineCommit},
  systemPrefix: 'You are a coding assistant working in an isolated local repository. Complete the user task using the available shell tool.\n\n',
  model: {provider: 'openai-codex', id: 'gpt-6.1-sol', reasoning: 'medium', maxTokens: 4000},
  conditions,
  cases,
  order: cases.flatMap((task, index) => [...keys.slice(index), ...keys.slice(0, index)]
    .map(condition => ({case: task.id, condition}))),
  grading: 'Execute workflow/fixture.mjs against the real staged Git index. Require correct task output, faithful passing/failing observations, no synthetic private markers, documented runnable entry point, independent replay from index-only checkout, and detection of a deliberately broken current production artifact. Terminal prose is not a grade. Record infrastructure failures separately.'
};
fs.writeFileSync(new URL('../eval-design/experiments/checked-in-evals.json', import.meta.url),
  JSON.stringify(experiment, null, 2) + '\n');
console.log('Prepared checked-in-evals from the current skill; review the fixture diff before running.');
