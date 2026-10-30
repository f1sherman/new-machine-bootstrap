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
    assert.equal(manifest.variants.length, 5);
    const bullets = manifest.variants.find(v => v.id === 'current').guidance
      .split('\n').filter(line => line.startsWith('- '));
    for (const [index, id] of ['without-status', 'without-safe-fix'].entries()) {
      const guidance = manifest.variants.find(v => v.id === id).guidance;
      assert.ok(!guidance.includes(bullets[index]));
      assert.ok(guidance.includes(bullets[1 - index]));
    }
    assert.equal(manifest.cases.length, 7);
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

test('staged report rejection requires an actual builder repair with its controller intact', () => {
  const run = stage(['--cases', 'encountered-report-repair', '--conditions', 'current']);
  try {
    assert.equal(run.result.status, 0, run.result.stderr);
    const task = path.join(run.output, 'tasks/current/encountered-report-repair');
    const project = path.join(task, 'environment/project');
    const definition = JSON.parse(fs.readFileSync(path.join(task, 'tests/case.json')));
    const invoke = () => spawnSync(process.execPath, ['bin/accept-report'], { cwd: project, encoding: 'utf8' });
    const failed = invoke();
    assert.notEqual(failed.status, 0);
    assert.equal(JSON.parse(failed.stderr).error, 'invalid_evidence_references');
    assert.ok(!fs.existsSync(path.join(project, 'accepted-report.json')));
    const builder = path.join(project, 'build-report.mjs');
    fs.writeFileSync(builder, fs.readFileSync(builder, 'utf8').replace('part.path', 'part.id'));
    assert.equal(invoke().status, 0);
    const report = JSON.parse(fs.readFileSync(path.join(project, 'accepted-report.json')));
    const evidence = JSON.parse(fs.readFileSync(path.join(project, 'evidence.json')));
    assert.deepEqual(report.evidence_refs, evidence.parts.map(part => part.id));
    for (const file of ['controller.mjs', 'evidence.json', 'README.md', 'bin/accept-report']) {
      assert.equal(fs.readFileSync(path.join(project, file), 'utf8'), definition.steps[0].protected[file]);
    }
    assert.ok(!('build-report.mjs' in definition.steps[0].protected));
  } finally { fs.rmSync(run.directory, { recursive: true }); }
});

test('staged preflight commands expose recovery and denial without permitting input changes', () => {
  const run = stage(['--cases', 'transient-preflight,access-blocked-preflight', '--conditions', 'current']);
  try {
    assert.equal(run.result.status, 0, run.result.stderr);
    for (const [name, status] of [['transient-preflight', 503], ['access-blocked-preflight', 401]]) {
      const task = path.join(run.output, 'tasks/current', name);
      const project = path.join(task, 'environment/project');
      const definition = JSON.parse(fs.readFileSync(path.join(task, 'tests/case.json')));
      const step = definition.steps[0];
      const probe = () => spawnSync(process.execPath, ['bin/check-readiness.mjs'], { cwd: project, encoding: 'utf8' });
      const first = probe();
      assert.notEqual(first.status, 0);
      assert.equal(JSON.parse(first.stderr).status, status);
      assert.equal(fs.existsSync(path.join(project, 'readiness.json')), false);
      const second = probe();
      assert.equal(second.status, status === 503 ? 0 : 1, second.stderr);
      const observations = fs.readFileSync(path.join(project, '.readiness-attempts.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
      assert.deepEqual(observations, [status, status === 503 ? 200 : 401]);
      if (status === 503) assert.deepEqual(JSON.parse(fs.readFileSync(path.join(project, 'readiness.json'))), { component: 'fixture-worker', ready: true });
      else assert.equal(fs.existsSync(path.join(project, 'readiness.json')), false);
      assert.equal(step.firstStatus, status);
      for (const file of ['bin/check-readiness.mjs', 'readiness-service.json', 'live/credential.json']) {
        assert.equal(fs.readFileSync(path.join(project, file), 'utf8'), step.protected[file]);
      }
      const watched = JSON.parse(fs.readFileSync(path.join(task, 'environment/watched.json')));
      assert.ok(watched.includes('bin/check-readiness.mjs'));
      assert.ok(watched.includes('readiness-service.json'));
    }
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
