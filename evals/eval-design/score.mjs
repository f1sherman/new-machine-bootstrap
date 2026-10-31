import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const [directory, ratingsFile] = process.argv.slice(2);
assert.ok(directory && ratingsFile, 'Usage: node score.mjs <audit-directory> <ratings.json>');
const results = JSON.parse(fs.readFileSync(path.join(directory, 'results.json')));
const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json')));
const {items} = JSON.parse(fs.readFileSync(ratingsFile));
assert.equal(new Set(items.map(item => item.label)).size, items.length, 'Duplicate rating');
assert.equal(items.length, results.responses.length, 'Rate every captured response');
const responses = results.responses.map(response => {
  const rating = items.find(item => item.label === response.label);
  const task = manifest.cases.find(task => task.id === response.case);
  assert.ok(rating && Array.isArray(rating.scores));
  assert.equal(rating.scores.length, task.criteria.length);
  assert.ok(rating.scores.every(value => Number.isInteger(value) && value >= 0 && value <= 2));
  const row = {case: response.case, condition: response.condition,
    generationComplete: response.generationComplete, stopReason: response.stopReason,
    text: response.text, contextSha256: response.contextSha256,
    scores: rating.scores, review: rating.reason};
  if (row.generationComplete && row.scores.every(value => value === 2)) {
    row.usage = Object.fromEntries(['input', 'output', 'cacheRead', 'cacheWrite', 'totalTokens']
      .map(key => [key, response.usage[key]]));
  }
  return row;
});
console.log(JSON.stringify({experiment: results.experiment,
  conditions: results.conditions, cases: results.cases, responses}, null, 2));
