import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const script = fileURLToPath(new URL('./run.mjs', import.meta.url));
const credential = 'fixture-access-credential-not-a-real-token';
function fixture(t) {
  fs.mkdirSync('tmp', {recursive: true});
  const root = fs.mkdtempSync(path.resolve('tmp/eval-design-runner-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  const calls = path.join(root, 'calls');
  fs.writeFileSync(path.join(bin, 'pi'), `#!/bin/sh
printf '.' >> "$CALLS_FILE"
if [ "$AUTH_FAIL" = 1 ]; then
  printf '%s' '${credential}' >&2
  exit 2
fi
printf '%s' '${credential}'
`, {mode: 0o755});
  const sdk = path.join(root, 'sdk.mjs');
  fs.writeFileSync(sdk, `export const getModel = () => ({});
export const completeSimple = async (_model, _context, options) => {
  throw new Error('Transport failed for Bearer ' + options.apiKey);
};
`);
  const output = path.join(root, 'output');
  return {root, calls, sdk, output, env: {...process.env,
    PATH: bin + path.delimiter + process.env.PATH, CALLS_FILE: calls}};
}
function run(fixture) {
  return spawnSync(process.execPath, [script, 'token-reporting',
    '--output', fixture.output, '--sdk-module', fixture.sdk],
  {encoding: 'utf8', env: fixture.env});
}

test('SDK failure retains its cause without a credential or an automatic retry', t => {
  const setup = fixture(t);
  const result = run(setup);
  assert.equal(result.status, 1);
  const raw = fs.readFileSync(path.join(setup.output, 'results.json'), 'utf8');
  const audit = JSON.parse(raw);
  assert.equal(audit.failure.stage, 'model-call');
  assert.equal(audit.failure.name, 'Error');
  assert.match(audit.failure.message, /Transport failed/);
  assert.match(audit.failure.message, /\[redacted\]/);
  assert.ok(!raw.includes(credential));
  assert.ok(!(result.stdout + result.stderr).includes(credential));
  assert.equal(fs.readFileSync(setup.calls, 'utf8'), '.');
  assert.equal(audit.complete, false);
});

test('credential-command failure records stage and exit status without copying stderr', t => {
  const setup = fixture(t);
  setup.env.AUTH_FAIL = '1';
  const result = run(setup);
  assert.equal(result.status, 1);
  const raw = fs.readFileSync(path.join(setup.output, 'results.json'), 'utf8');
  const audit = JSON.parse(raw);
  assert.equal(audit.failure.stage, 'authentication');
  assert.equal(audit.failure.exitStatus, 2);
  assert.ok(!raw.includes(credential));
  assert.ok(!(result.stdout + result.stderr).includes(credential));
  assert.equal(fs.readFileSync(setup.calls, 'utf8'), '.');
  assert.equal(audit.responses.length, 0);
});
