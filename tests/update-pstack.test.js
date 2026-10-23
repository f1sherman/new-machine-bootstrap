import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import test from 'node:test';

const updater = path.resolve('bin/update-pstack');
const vendor = 'roles/common/files/vendor/pstack';
function git(root, ...args) {
  return execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
}
function write(root, name, text) {
  const file = path.join(root, name);
  mkdirSync(path.dirname(file), {recursive: true});
  writeFileSync(file, text);
}
function fixture(fn) {
  const root = mkdtempSync(path.join(tmpdir(), 'pstack-update-'));
  const source = path.join(root, 'source');
  const consumer = path.join(root, 'consumer');
  mkdirSync(source);
  mkdirSync(consumer);
  git(source, 'init', '-q');
  git(source, 'config', 'user.name', 'Fixture');
  git(source, 'config', 'user.email', 'fixture@example.com');
  for (const name of ['how', 'poteto-mode', 'poteto-help']) {
    write(source, `pstack/skills/${name}/SKILL.md`, `# ${name}\n`);
  }
  write(source, 'pstack/skills/how/references/detail.md', 'support\n');
  write(source, 'pstack/skills/how/scripts/run', '#!/bin/sh\nprintf ok\n');
  chmodSync(path.join(source, 'pstack/skills/how/scripts/run'), 0o755);
  write(source, 'pstack/LICENSE', 'MIT fixture\n');
  write(source, 'pstack/README.md', 'readme\n');
  write(source, 'pstack/agents/poteto-agent.md', 'agent\n');
  write(source, 'pstack/docs/harness/claude-code.md', 'adapter\n');
  write(source, 'pstack/assets/excluded.txt', 'exclude\n');
  write(source, 'other/SKILL.md', 'exclude\n');
  write(source, 'cursor-team-kit/skills/deslop/SKILL.md', '# deslop\n');
  write(source, 'cursor-team-kit/LICENSE', 'MIT external fixture\n');
  const commit = () => {
    git(source, 'add', '-A');
    git(source, 'commit', '-qm', 'fixture');
    return git(source, 'rev-parse', 'HEAD');
  };
  const pin = (sha) => write(consumer, 'vars/tool_versions.yml', `tool_versions:\n  git_commits:\n    pstack: ${sha}\n`);
  pin(commit());
  const run = (...args) => spawnSync('python3', [updater, '--repo-root', consumer, '--source', source, ...args], {encoding: 'utf8'});
  const generated = (name) => path.join(consumer, vendor, name);
  try { fn({root, source, consumer, commit, pin, run, generated}); }
  finally { rmSync(root, {recursive: true, force: true}); }
}
function pass(result) { assert.equal(result.status, 0, result.stderr); }
function interruptedUpdate(f, rollbackFails = false) {
  const script = `
import pathlib, runpy, sys
namespace = runpy.run_path(sys.argv[1], run_name='updater_test')
original = pathlib.Path.rename
rollback_fails = sys.argv[4] == 'true'
def rename(source, target):
    if source.name == 'generated':
        raise KeyboardInterrupt('injected publication interruption')
    if rollback_fails and source.name in {'previous', 'snapshot'}:
        raise OSError('injected rollback failure')
    return original(source, target)
pathlib.Path.rename = rename
sys.argv = [sys.argv[1], '--repo-root', sys.argv[2], '--source', sys.argv[3]]
namespace['main']()
`;
  return spawnSync('python3', ['-c', script, updater, f.consumer, f.source, String(rollbackFails)], {encoding: 'utf8'});
}

test('copies the exact pin with complete support files and executable modes', () => fixture((f) => {
  write(f.source, 'pstack/README.md', 'newer unpinned content\n');
  f.commit();
  pass(f.run());
  assert.equal(readFileSync(f.generated('README.md'), 'utf8'), 'readme\n');
  assert.equal(readFileSync(f.generated('skills/how/references/detail.md'), 'utf8'), 'support\n');
  assert.equal(statSync(f.generated('skills/how/scripts/run')).mode & 0o777, 0o755);
  assert.equal(existsSync(f.generated('assets')), false);
  assert.equal(existsSync(f.generated('other')), false);
  pass(f.run('--check'));
}));

test('preserves raw selected files despite upstream export attributes', () => fixture((f) => {
  write(f.source, 'pstack/.gitattributes', 'skills/how/references/detail.md export-ignore\nskills/how/references/raw.md export-subst\n');
  write(f.source, 'pstack/skills/how/references/raw.md', '$Format:%H$\n');
  f.pin(f.commit());
  pass(f.run());
  assert.equal(readFileSync(f.generated('skills/how/references/detail.md'), 'utf8'), 'support\n');
  assert.equal(readFileSync(f.generated('skills/how/references/raw.md'), 'utf8'), '$Format:%H$\n');
}));

test('rejects destination and ancestor symlinks without changing external files', () => {
  for (const ancestor of [false, true]) fixture((f) => {
    pass(f.run());
    const destination = ancestor ? path.dirname(f.generated('')) : f.generated('');
    const external = path.join(f.root, 'external');
    renameSync(destination, external);
    symlinkSync(external, destination);
    const manifest = ancestor ? path.join(external, 'pstack/SHA256SUMS') : path.join(external, 'SHA256SUMS');
    const before = readFileSync(manifest, 'utf8');
    assert.notEqual(f.run('--check').status, 0);
    write(f.source, 'pstack/README.md', 'new pin\n');
    f.pin(f.commit());
    assert.notEqual(f.run().status, 0);
    assert.equal(readFileSync(manifest, 'utf8'), before);
  });
});

test('restores the previous snapshot after publication interruption', () => fixture((f) => {
  pass(f.run());
  const before = readFileSync(f.generated('SHA256SUMS'), 'utf8');
  write(f.source, 'pstack/README.md', 'new pin\n');
  f.pin(f.commit());
  assert.notEqual(interruptedUpdate(f).status, 0);
  assert.equal(readFileSync(f.generated('SHA256SUMS'), 'utf8'), before);
}));

test('keeps a recoverable backup if restoration also fails', () => fixture((f) => {
  pass(f.run());
  const before = readFileSync(f.generated('SHA256SUMS'), 'utf8');
  write(f.source, 'pstack/README.md', 'new pin\n');
  f.pin(f.commit());
  const result = interruptedUpdate(f, true);
  assert.notEqual(result.status, 0);
  const parent = path.dirname(f.generated(''));
  const backups = readdirSync(parent).filter(name => name.startsWith('.pstack-backup-'));
  assert.equal(backups.length, 1, result.stderr);
  assert.equal(readFileSync(path.join(parent, backups[0], 'snapshot/SHA256SUMS'), 'utf8'), before);
  assert.match(result.stderr, /backup/);
  const retry = f.run();
  assert.notEqual(retry.status, 0);
  assert.match(retry.stderr, /backup needs recovery/);
  assert.equal(readFileSync(path.join(parent, backups[0], 'snapshot/SHA256SUMS'), 'utf8'), before);
}));

test('new pins remove stale files and generate a reproducible snapshot', () => fixture((f) => {
  pass(f.run());
  rmSync(path.join(f.source, 'pstack/skills/how/references/detail.md'));
  write(f.source, 'pstack/skills/how/references/new.md', 'new support\n');
  f.pin(f.commit());
  pass(f.run());
  assert.equal(existsSync(f.generated('skills/how/references/detail.md')), false);
  assert.equal(readFileSync(f.generated('skills/how/references/new.md'), 'utf8'), 'new support\n');
  pass(f.run('--check'));
}));

test('check detects extra, changed, missing, and executable-mode changes without writing', () => {
  for (const kind of ['extra', 'changed', 'missing', 'mode']) fixture((f) => {
    pass(f.run());
    const file = f.generated('skills/how/SKILL.md');
    if (kind === 'extra') write(f.consumer, `${vendor}/extra.md`, 'extra\n');
    if (kind === 'changed') writeFileSync(file, 'changed\n');
    if (kind === 'missing') rmSync(file);
    if (kind === 'mode') chmodSync(file, 0o755);
    const result = f.run('--check');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /differs/);
    if (kind === 'extra') assert.equal(existsSync(f.generated('extra.md')), true);
    if (kind === 'changed') assert.equal(readFileSync(file, 'utf8'), 'changed\n');
    if (kind === 'missing') assert.equal(existsSync(file), false);
    if (kind === 'mode') assert.equal(statSync(file).mode & 0o777, 0o755);
  });
});

test('rejects unsafe or incomplete upstream before replacing the previous snapshot', () => {
  for (const kind of ['symlink', 'missing-license', 'missing-skill', 'invalid-pin', 'external-symlink', 'external-missing-license', 'external-missing-skill']) fixture((f) => {
    pass(f.run());
    const before = readFileSync(f.generated('SHA256SUMS'), 'utf8');
    if (kind === 'symlink') symlinkSync('/etc/passwd', path.join(f.source, 'pstack/skills/how/leak'));
    if (kind === 'missing-license') rmSync(path.join(f.source, 'pstack/LICENSE'));
    if (kind === 'missing-skill') rmSync(path.join(f.source, 'pstack/skills/how/SKILL.md'));
    if (kind === 'external-symlink') symlinkSync('/etc/passwd', path.join(f.source, 'cursor-team-kit/skills/deslop/leak'));
    if (kind === 'external-missing-license') rmSync(path.join(f.source, 'cursor-team-kit/LICENSE'));
    if (kind === 'external-missing-skill') rmSync(path.join(f.source, 'cursor-team-kit/skills/deslop/SKILL.md'));
    if (kind === 'invalid-pin') f.pin('main');
    else f.pin(f.commit());
    const result = f.run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /regular|missing|SHA/);
    assert.equal(readFileSync(f.generated('SHA256SUMS'), 'utf8'), before);
  });
});
