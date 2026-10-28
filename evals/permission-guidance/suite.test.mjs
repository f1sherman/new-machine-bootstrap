import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { collectPermission } from './suite.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
fs.mkdirSync(path.join(root, 'tmp'), { recursive: true });
function stage(extra = []) {
  const directory = fs.mkdtempSync(path.join(root, 'tmp/permission-stage-test-'));
  const skill = path.join(directory, 'skill.md');
  fs.writeFileSync(skill, '# Fixed test skill\nApproval checkpoint for the test skill.\n');
  const output = path.join(directory, 'output');
  const result = spawnSync(process.execPath, ['evals/harbor/run.mjs', '--suite', 'permission-guidance',
    '--model', 'openai/gpt-6.1-sol', '--skill-file', skill, '--output', output, ...extra], { cwd: root, encoding: 'utf8' });
  return { directory, output, result };
}

test('shared driver stages native continued workflows and excludes holdouts by default', () => {
  const run = stage(['--compare-ref', 'HEAD', '--ablate']);
  try {
    assert.equal(run.result.status, 0, run.result.stderr);
    const manifest = JSON.parse(fs.readFileSync(path.join(run.output, 'manifest.json')));
    assert.equal(manifest.variants.length, 6);
    assert.equal(manifest.cases.length, 4);
    assert.ok(manifest.cases.every(c => c.split === 'development'));
    assert.equal(manifest.agent, 'pi');
    assert.equal(manifest.resume, true);
    const task = path.join(run.output, 'tasks/current/explicit-checkpoint');
    const bin = path.join(run.directory, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'python3'), '#!/bin/sh\nprintf "%s\\n" "$@"\n', { mode: 0o755 });
    for (const name of ['design', 'approved']) {
      const script = path.join(task, 'steps', name, 'tests/test.sh');
      const invocation = spawnSync('/bin/sh', [script], { encoding: 'utf8', env: { PATH: bin } });
      assert.equal(invocation.status, 0, invocation.stderr);
      assert.equal(invocation.stdout, `/tests/verify.py\n${name}\n`);
    }
    const definition = JSON.parse(fs.readFileSync(path.join(task, 'tests/case.json')));
    assert.ok('app.mjs' in definition.steps[0].protected);
    assert.ok(!('app.mjs' in definition.steps[1].protected));
    assert.equal(definition.steps[0].protected['records.json'], '[{"id":"account-1","name":"Ada","history":"only copy"}]\n');
    const assessment = JSON.parse(fs.readFileSync(path.join(run.output, 'report.json')));
    assert.equal(assessment.results.length, 0, 'Staging must not execute trials');
  } finally { fs.rmSync(run.directory, { recursive: true }); }
});

test('holdout selection is explicit and a conflicting replay override is refused', () => {
  const run = stage(['--cases', 'spec-only', '--conditions', 'current']);
  try {
    assert.equal(run.result.status, 0, run.result.stderr);
    const manifest = JSON.parse(fs.readFileSync(path.join(run.output, 'manifest.json')));
    assert.equal(manifest.cases[0].split, 'holdout');
    const bad = spawnSync(process.execPath, ['evals/harbor/run.mjs', '--replay', run.output,
      '--skill-file', 'changed.md', '--output', path.join(run.directory, 'replay')], { cwd: root, encoding: 'utf8' });
    assert.notEqual(bad.status, 0);
  } finally { fs.rmSync(run.directory, { recursive: true }); }
});

test('collection rejects a switched session instead of publishing a false continued-workflow pass', () => {
  const directory = fs.mkdtempSync(path.join(root, 'tmp/permission-collect-'));
  try {
    for (const [step, sessionId] of [['design', 'one'], ['approved', 'two']]) {
      const folder = path.join(directory, 'steps', step, 'verifier');
      fs.mkdirSync(folder, { recursive: true });
      fs.writeFileSync(path.join(folder, 'assessment.json'), JSON.stringify({ task: true, authority: true,
        sessionId, usage: { input: 10, output: 5, cacheRead: 0, cacheWrite: 0 } }));
      fs.writeFileSync(path.join(folder, 'reward.json'), JSON.stringify({ reward: 1, task: 1, authority: 1 }));
    }
    const result = { step_results: [{ step_name: 'design' }, { step_name: 'approved' }] };
    const read = file => JSON.parse(fs.readFileSync(file));
    assert.throws(() => collectPermission(result, { steps: ['design', 'approved'] }, directory, read), /session changed/);
    const file = path.join(directory, 'steps/approved/verifier/assessment.json');
    fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replace('"two"', '"one"'));
    const collected = collectPermission(result, { steps: ['design', 'approved'] }, directory, read);
    assert.deepEqual(collected.checks, { task: true, authority: true });
    assert.equal(collected.usage.input, 20);
  } finally { fs.rmSync(directory, { recursive: true }); }
});
