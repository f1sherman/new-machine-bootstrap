import fs from 'node:fs';
import assert from 'node:assert/strict';

const file = process.argv[2];
assert.ok(file, 'Usage: node report.mjs <scored-results.json|->');
const data = JSON.parse(fs.readFileSync(file === '-' ? 0 : file, 'utf8'));
const {conditions, cases, responses} = data;
assert.ok(conditions.length && cases.length);
assert.equal(new Set(conditions).size, conditions.length);
assert.equal(new Set(cases).size, cases.length);
const indexed = new Map();
for (const response of responses) {
  assert.ok(conditions.includes(response.condition) && cases.includes(response.case));
  assert.equal(typeof response.generationComplete, 'boolean');
  const key = JSON.stringify([response.condition, response.case]);
  assert.ok(!indexed.has(key), 'Duplicate response');
  if (response.scores) {
    assert.ok(response.scores.length > 0);
    assert.ok(response.scores.every(value => Number.isInteger(value) && value >= 0 && value <= 2));
  }
  indexed.set(key, response);
}
const get = (condition, task) => indexed.get(JSON.stringify([condition, task]));
const success = response => response?.generationComplete === true &&
  response.scores?.length > 0 && response.scores.every(value => value === 2);
const counts = Object.fromEntries(conditions.map(condition => {
  const rows = cases.map(task => get(condition, task));
  const successes = rows.filter(success).length;
  const incompleteGenerations = rows.filter(row => row?.generationComplete === false).length;
  const ungraded = rows.filter(row => !row ||
    (row.generationComplete === true && !row.scores)).length;
  return [condition, {successes,
    failures: rows.length - successes - incompleteGenerations - ungraded,
    incompleteGenerations, ungraded}];
}));
const ready = Object.values(counts).every(count => count.ungraded === 0);
const matchedSuccessfulCases = ready ? cases.filter(task =>
  conditions.every(condition => success(get(condition, task)))) : [];
const successfulTokenTotals = matchedSuccessfulCases.length ?
  Object.fromEntries(conditions.map(condition => {
    const total = {input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0};
    for (const task of matchedSuccessfulCases) {
      const usage = get(condition, task).usage;
      for (const key of Object.keys(total)) {
        assert.ok(Number.isFinite(usage?.[key]) && usage[key] >= 0,
          'A successful matched response needs complete usage');
        total[key] += usage[key];
      }
    }
    return [condition, total];
  })) : null;
console.log(JSON.stringify({experiment: data.experiment, ready, counts,
  matchedSuccessfulCases, successfulTokenTotals}, null, 2));
