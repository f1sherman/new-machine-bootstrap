import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const [original,regraded,destination]=process.argv.slice(2);
assert.ok(original && regraded && destination,
  'Usage: node publish.mjs <private-original-run> <regraded-run> <new-directory>');
fs.mkdirSync(destination);
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const receipts={};
const save=(name,data)=>{
  const bytes=JSON.stringify(data,null,2)+'\n';
  fs.writeFileSync(path.join(destination,name),bytes);
  receipts[name]=hash(bytes);
};
const read=(directory,name)=>JSON.parse(fs.readFileSync(path.join(directory,name)));
const manifest=read(original,'manifest.json');
delete manifest.runtime.owner;
delete manifest.runtime.cleanup;
manifest.publicEvidence={scope:'Actual staged changes and tool results; provider reasoning and IDs excluded. Synthetic privacy markers are fixture data, not credentials.',
  originalManifestSha256:hash(fs.readFileSync(path.join(original,'manifest.json'))),
  regradedManifestSha256:hash(fs.readFileSync(path.join(regraded,'manifest.json'))),
  graderSha256:read(regraded,'manifest.json').replay.fixtureSha256};
save('manifest.json',manifest);
const results=read(regraded,'results.json');
for (const row of results) {
  const file=`${row.case}-${row.condition}.json`;
  const raw=read(original,file);
  const revised=read(regraded,file);
  const record={case:row.case,condition:row.condition,complete:row.complete,
    initialResponseTimestamp:raw.initialResponseTimestamp ?? raw.turns?.[0]?.response.timestamp,
    originalHead:revised.originalHead ?? raw.originalHead,
    initialCommit:revised.initialCommit ?? raw.initialCommit,
    terminal:raw.terminal,tools:raw.tools ?? [],diff:raw.diff,error:raw.error,
    assessment:revised.assessment ? {checks:revised.assessment.checks,pass:revised.assessment.pass,
      files:revised.assessment.files,replays:revised.assessment.replays} : undefined,
    supersededChecks:raw.assessment?.checks};
  if (row.complete && row.pass) {
    record.usage=Object.fromEntries(['input','output','cacheRead','cacheWrite','totalTokens']
      .map(key=>[key,raw.turns.reduce((sum,turn)=>sum+turn.response.usage[key],0)]));
  }
  const text=JSON.stringify(record);
  assert.ok(!/thinkingSignature|encrypted_content|Bearer |\/Users\//.test(text),
    'Possible private runtime field; inspect before publication');
  save(file,record);
}
save('results.json',results);
fs.writeFileSync(path.join(destination,'receipts.json'),JSON.stringify(receipts,null,2)+'\n');
console.log('Exported allowlisted workflow evidence. Review the files before committing.');
