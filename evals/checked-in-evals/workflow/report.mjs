import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const directory=process.argv[2];
assert.ok(directory,'Usage: node report.mjs <published-record-directory>');
const receipts=JSON.parse(fs.readFileSync(path.join(directory,'receipts.json')));
for(const [file,expected] of Object.entries(receipts)) {
  assert.equal(path.basename(file),file);
  const actual=crypto.createHash('sha256').update(fs.readFileSync(path.join(directory,file))).digest('hex');
  assert.equal(actual,expected,'Evidence changed: '+file);
}
const manifest=JSON.parse(fs.readFileSync(path.join(directory,'manifest.json')));
const results=JSON.parse(fs.readFileSync(path.join(directory,'results.json')));
const conditions=Object.keys(manifest.conditions);
const cases=manifest.cases.map(row=>row.id);
assert.equal(results.length,conditions.length*cases.length,'Incomplete matrix');
const counts={};
for(const condition of conditions) {
  const rows=results.filter(row=>row.condition===condition);
  assert.deepEqual(rows.map(row=>row.case).sort(),[...cases].sort(),'Duplicate or missing case');
  counts[condition]={passes:rows.filter(row=>row.complete && row.pass).length,
    failures:rows.filter(row=>row.complete && !row.pass).length,
    incomplete:rows.filter(row=>!row.complete).length};
}
const successfulConditions=conditions.filter(condition=>counts[condition].passes===cases.length);
const matchedSuccessfulTokens={};
for(const condition of successfulConditions) {
  const totals={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0};
  for(const task of cases) {
    const record=JSON.parse(fs.readFileSync(path.join(directory,`${task}-${condition}.json`)));
    for(const key of Object.keys(totals)) {
      assert.ok(Number.isFinite(record.usage[key]));totals[key]+=record.usage[key];
    }
  }
  matchedSuccessfulTokens[condition]=totals;
}
console.log(JSON.stringify({counts,matchedTokenCases:cases,matchedSuccessfulTokens,
  limit:'Token comparisons exclude failed/incomplete workflows. No comparison with a failing baseline is supported.'},null,2));
