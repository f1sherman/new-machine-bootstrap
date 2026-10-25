import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import test from 'node:test';

const script = path.resolve('roles/common/files/vendor/pstack/skills/statechart/scripts/statechart.mjs');

for (const location of ['tlc/notes.md', 'tlc/fixed/notes.md', 'tlc/unexpected/notes.md', 'chart.mmd/notes.md']) {
  test(`refuses output replacement with ${location}`, () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'pstack-safety-'));
    try {
      writeFileSync(path.join(dir, 'Check.tla'), '---- MODULE Check ----\nVARIABLE x\nInit == x = 0\nNext == x\' = x\n====\n');
      writeFileSync(path.join(dir, 'Check.cfg'), 'INIT Init\nNEXT Next\n');
      const note = path.join(dir, 'Check-statechart', location);
      mkdirSync(path.dirname(note), {recursive: true});
      writeFileSync(note, 'user work\n');
      const r = spawnSync(process.execPath, [script, 'from-spec', 'Check.tla'], {
        cwd: dir, encoding: 'utf8', timeout: 15000,
      });
      assert.equal(r.status, 2, r.stderr);
      assert.match(r.stderr, /file[s]? that this command did not write/);
      assert.match(r.stderr, /notes\.md|tlc\/unexpected|chart\.mmd/);
      assert.equal(readFileSync(note, 'utf8'), 'user work\n');
    } finally {
      rmSync(dir, {recursive: true, force: true});
    }
  });
}

test('refuses a TLC directory symlink without touching its target', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'pstack-safety-'));
  try {
    writeFileSync(path.join(dir, 'Check.tla'), '---- MODULE Check ----\nVARIABLE x\nInit == x = 0\nNext == x\' = x\n====\n');
    writeFileSync(path.join(dir, 'Check.cfg'), 'INIT Init\nNEXT Next\n');
    const out = path.join(dir, 'Check-statechart');
    const external = path.join(dir, 'external');
    mkdirSync(out); mkdirSync(external);
    writeFileSync(path.join(external, 'notes.md'), 'user work\n');
    symlinkSync(external, path.join(out, 'tlc'));
    const r = spawnSync(process.execPath, [script, 'from-spec', 'Check.tla'], {
      cwd: dir, encoding: 'utf8', timeout: 15000,
    });
    assert.equal(r.status, 2, r.stderr);
    assert.match(r.stderr, /file[s]? that this command did not write/);
    assert.equal(readFileSync(path.join(external, 'notes.md'), 'utf8'), 'user work\n');
  } finally { rmSync(dir, {recursive: true, force: true}); }
});
