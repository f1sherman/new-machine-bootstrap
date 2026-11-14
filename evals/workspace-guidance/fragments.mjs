import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

export function stageFragmentComparison(repo, output, fragment) {
  assert.equal(path.basename(fragment), fragment, 'Fragment must be a filename');
  const source = path.join(repo, 'roles/common/files/pi/base-fragments');
  const base = path.join(repo, 'roles/common/files/pi/AGENTS.md.d/00-base.md');
  const assembler = path.join(repo, 'bin/assemble-guidance');
  const files = fs.readdirSync(source).filter(name => name.endsWith('.md')).sort();
  assert.ok(files.includes(fragment), 'Unknown guidance fragment');
  execFileSync(assembler, ['--check', source, base]);

  const withoutDir = path.join(output, 'without');
  const removedDir = path.join(output, 'removed');
  fs.mkdirSync(withoutDir, {recursive: true});
  fs.mkdirSync(removedDir, {recursive: true});
  for (const file of files) {
    fs.copyFileSync(path.join(source, file), path.join(file === fragment ? removedDir : withoutDir, file));
  }
  const removedFile = path.join(output, 'removed.md');
  const withoutFile = path.join(output, 'without.md');
  execFileSync(assembler, [removedDir, removedFile, withoutDir, withoutFile]);
  const current = fs.readFileSync(base, 'utf8');
  const removed = fs.readFileSync(removedFile, 'utf8');
  const without = fs.readFileSync(withoutFile, 'utf8');
  assert.ok(removed && current.includes(removed), 'Fragment is absent from assembled guidance');
  assert.equal(current.indexOf(removed), current.lastIndexOf(removed), 'Fragment contribution is ambiguous');
  assert.equal(current.replace(removed, ''), without, 'Comparison changes more than one fragment');
  return {current, without, removed};
}
