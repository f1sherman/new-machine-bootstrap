import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const script = fileURLToPath(new URL('./report.mjs', import.meta.url));
const usage = totalTokens => ({input: totalTokens, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens});
const row = (condition, task, scores, tokens) => ({condition, case: task,
  generationComplete: true, scores, usage: usage(tokens)});
function report(cases, responses) {
  const result = spawnSync(process.execPath, [script, '-'], {encoding: 'utf8',
    input: JSON.stringify({experiment: 'fixture', conditions: ['A', 'B'], cases, responses})});
  assert.equal(result.status, 0, result.stderr);
  return {value: JSON.parse(result.stdout), text: result.stdout};
}

test('cost comparison uses only the same successful cases and never prints failure usage', () => {
  const {value, text} = report(['one', 'two', 'three'], [
    row('A', 'one', [2, 2], 100), row('B', 'one', [2, 2], 80),
    row('A', 'two', [2, 2], 200), row('B', 'two', [0, 2], 899999),
    row('A', 'three', [1, 2], 799999), row('B', 'three', [2, 2], 300)
  ]);
  assert.deepEqual(value.matchedSuccessfulCases, ['one']);
  assert.deepEqual(value.counts.A, {successes: 2, failures: 1, incompleteGenerations: 0, ungraded: 0});
  assert.deepEqual(value.counts.B, {successes: 2, failures: 1, incompleteGenerations: 0, ungraded: 0});
  assert.equal(value.successfulTokenTotals.A.totalTokens, 100);
  assert.equal(value.successfulTokenTotals.B.totalTokens, 80);
  assert.ok(!text.includes('899999') && !text.includes('799999'));
});

test('no successful shared cases means no token comparison', () => {
  const {value, text} = report(['one'], [row('A', 'one', [0], 999999), row('B', 'one', [0], 888888)]);
  assert.equal(value.successfulTokenTotals, null);
  assert.deepEqual(value.matchedSuccessfulCases, []);
  assert.equal(value.counts.A.failures, 1);
  assert.ok(!text.includes('999999') && !text.includes('888888'));
});

test('an incomplete generation is separate from a graded answer failure', () => {
  const incomplete = {...row('B', 'one', [2], 666666), generationComplete: false};
  const {value, text} = report(['one'], [row('A', 'one', [2], 100), incomplete]);
  assert.equal(value.counts.B.incompleteGenerations, 1);
  assert.equal(value.counts.B.failures, 0);
  assert.equal(value.successfulTokenTotals, null);
  assert.ok(!text.includes('666666'));
});

test('an ungraded response cannot silently become a success or a token comparison', () => {
  const pending = row('B', 'one', undefined, 777777);
  const {value, text} = report(['one'], [row('A', 'one', [2], 100), pending]);
  assert.equal(value.ready, false);
  assert.equal(value.counts.B.ungraded, 1);
  assert.equal(value.successfulTokenTotals, null);
  assert.ok(!text.includes('777777'));
});
