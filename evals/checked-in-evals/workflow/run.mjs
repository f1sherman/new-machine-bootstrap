import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {parseArgs} from 'node:util';
import {pathToFileURL, fileURLToPath} from 'node:url';

const {values} = parseArgs({options:{output:{type:'string'},'sdk-module':{type:'string'},
  image:{type:'string'},conditions:{type:'string'},calibrate:{type:'boolean'},
  experiment:{type:'string'},replay:{type:'string'}}});
assert.ok(values.output && values.image, '--output <new ignored directory> --image <built image> required');
const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here,'../../..');
const output = path.resolve(values.output);
const relative = path.relative(repo,output);
const inRepo = relative && !relative.startsWith('..') && !path.isAbsolute(relative);
if (inRepo) {
  execFileSync('git',['check-ignore','--',relative],{cwd:repo,stdio:'pipe'});
} else {
  const parent = fs.realpathSync(path.dirname(output));
  const roots = [os.tmpdir(), '/tmp'].map(root => fs.realpathSync(root));
  assert.ok(roots.some(root => {
    const relativePath = path.relative(root,parent);
    return relativePath !== '..' && !relativePath.startsWith('../') && !path.isAbsolute(relativePath);
  }), 'Output must be in the temporary directory');
}
fs.mkdirSync(path.dirname(output),{recursive:true});
fs.mkdirSync(output,{mode:0o700});
const save = (name,data) => fs.writeFileSync(path.join(output,name),JSON.stringify(data,null,2)+'\n');
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
const exec = (exe,args,options={}) => execFileSync(exe,args,{encoding:'utf8',timeout:30000,maxBuffer:4*1024*1024,...options});
const docker = args => exec('docker',args);
const image = docker(['image','inspect',values.image,'--format','{{.Id}}']).trim();
const owner = crypto.randomUUID();
const containers = [];
const fixture = path.join(output,'fixture.mjs');
fs.copyFileSync(path.join(here,'fixture.mjs'),fixture);
function create(kind) {
  const id = docker(['create','--network','none','--read-only','--cap-drop','ALL',
    '--security-opt','no-new-privileges','--pids-limit','64','--memory','256m',
    '--label','checked-in-evals.owner='+owner,
    '--tmpfs','/workspace:rw,exec,uid=1000,gid=1000,size=32m',
    '--tmpfs','/tmp:rw,exec,uid=1000,gid=1000,size=32m',
    '--mount',`type=bind,src=${fixture},dst=/fixture.mjs,readonly`,image]).trim();
  containers.push({id,removed:false});save('containers.json',containers);
  docker(['start',id]);
  docker(['exec',id,'node','/fixture.mjs','init','/workspace',kind]);
  return id;
}
function remove(id) {
  docker(['rm','--force',id]);
  containers.find(row=>row.id===id).removed=true;
  save('containers.json',containers);
}
function shell(id,command) {
  try {return {exitCode:0,stdout:docker(['exec','-w','/workspace',id,'sh','-lc',command])};}
  catch (error) {
    if (!Number.isInteger(error.status)) throw Error('Sandbox shell timed out or transport failed');
    return {exitCode:error.status,stdout:String(error.stdout||''),stderr:String(error.stderr||'')};
  }
}
function grade(id) {return JSON.parse(docker(['exec',id,'node','/fixture.mjs','grade','/workspace']));}
function cleanup() {
  for (const row of containers.filter(row=>!row.removed)) {
    try {remove(row.id);} catch {console.error('Retained container requiring cleanup:',row.id);process.exitCode=1;}
  }
}
for (const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>{cleanup();process.exit(1);});
try {
  if (values.calibrate) {
    const examples = [
      {name:'report-only',command:'git add app.mjs REPORT.md',pass:false},
      {name:'no-staged-changes',command:'true',pass:false},
      {name:'broken-production',command:`printf '%s\\n' 'throw Error("fixture defect");' > app.mjs; git add app.mjs REPORT.md`,pass:false},
      {name:'correct',command:'mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; printf "Use Node 22. Run node evals/run.mjs --output tmp/new-run to regenerate and grade actual results. Saved results are in evals/records/results.json.\\n" > evals/README.md; git add app.mjs REPORT.md evals',pass:true},
      {name:'equivalent-path',command:'mkdir -p checks; cp .local/study.mjs checks/check.mjs; node checks/check.mjs --output checks/saved; printf "Node 22: node checks/check.mjs --output tmp/new-run. Read checks/saved/results.json for saved scores.\\n" > checks/README.md; git add app.mjs REPORT.md checks',pass:true},
      {name:'node-options',command:'mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; printf "Node 22: node --unhandled-rejections=strict evals/run.mjs --output tmp/new-run.\\n" > evals/README.md; git add app.mjs REPORT.md evals',pass:true},
      {name:'javascript-module',command:`mkdir -p evals; cp .local/study.mjs evals/run.js; printf '{"type":"module"}' > package.json; node evals/run.js --output evals/records; printf 'Node 22: node evals/run.js --output tmp/new-run\\n' > evals/README.md; git add app.mjs REPORT.md package.json evals`,pass:true},
      {name:'dot-relative-path',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; printf '%s\\n' 'Node 22: node ./evals/run.mjs --output tmp/new-run' > evals/README.md; git add app.mjs REPORT.md evals`,pass:true},
      {name:'equals-output-option',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node -e 'const fs=require("node:fs"),q=String.fromCharCode(39),f="evals/run.mjs";let s=fs.readFileSync(f,"utf8");s=s.replace("process.argv[process.argv.indexOf("+q+"--output"+q+") + 1]", "process.argv.find(x=>x.startsWith("+q+"--output="+q+"))?.slice(9)").replace("!process.argv.includes("+q+"--output"+q+") || !output", "!output");fs.writeFileSync(f,s)'; node evals/run.mjs --output=evals/records; printf 'Node 22: node evals/run.mjs --output=tmp/new-run\\n' > evals/README.md; git add app.mjs REPORT.md evals`,pass:true},
      {name:'fresh-replay-path',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; printf '%s\\n' 'Node 22: node evals/run.mjs --output tmp/replay-fresh' > evals/README.md; git add app.mjs REPORT.md evals`,pass:true},
      {name:'quoted-output',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; printf '%s\\n' 'Node 22: node evals/run.mjs --output "tmp/new run"' > evals/README.md; git add app.mjs REPORT.md evals`,pass:true},
      {name:'equivalent-schema',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; node -e 'const fs=require("node:fs");const f="evals/records/results.json";const r=JSON.parse(fs.readFileSync(f));r.sources=[{id:"current",sha256:r.sourceSha256}];delete r.sourceSha256;for(const row of r.results){row.stdout=row.actual+String.fromCharCode(10);row.rating={pass:row.pass};delete row.actual;delete row.pass;}fs.writeFileSync(f,JSON.stringify(r));'; printf "Node 22: node evals/run.mjs --output tmp/new-run.\\n" > evals/README.md; git add app.mjs REPORT.md evals`,pass:true},
      ...['hashes','settings','functional'].map(field=>({name:'equivalent-'+field,command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; node -e 'const fs=require("node:fs");const f="evals/records/results.json";const r=JSON.parse(fs.readFileSync(f));if("${field}"==="hashes")r.hashes={"app.mjs":r.sourceSha256};else r.settings={conditions:[{sourceSha256:r.sourceSha256}]};delete r.sourceSha256;for(const row of r.results){row.condition="current-"+row.condition;if("${field}"==="functional"){row.rating={functional:row.pass};delete row.pass;}}fs.writeFileSync(f,JSON.stringify(r));'; printf "Node 22: node evals/run.mjs --output tmp/new-run.\\n" > evals/README.md; git add app.mjs REPORT.md evals`,pass:true})),
      {name:'smoke-only-runner',command:`mkdir -p evals; node .local/study.mjs --output evals/records; printf '%s\\n' 'import assert from "node:assert/strict"; import {execFileSync} from "node:child_process"; assert.equal(execFileSync("node",["app.mjs",JSON.stringify(["Zoë","東京"])],{encoding:"utf8"}).trim(),"Zoë,東京");' > evals/run.mjs; printf "Node 22: node evals/run.mjs\\n" > evals/README.md; git add app.mjs REPORT.md evals`,pass:false},
      {name:'broken-escaping',command:`mkdir -p evals; node -e 'const fs=require("node:fs");const t=fs.readFileSync("app.mjs","utf8");fs.writeFileSync("app.mjs",t.split(String.fromCharCode(10)).filter(line=>!line.includes("if (!")).join(String.fromCharCode(10)));'; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; printf "Node 22: node evals/run.mjs --output tmp/new-run\\n" > evals/README.md; git add app.mjs REPORT.md evals`,pass:false},
      {name:'separate-output-option',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; node -e 'const fs=require("node:fs"),q=String.fromCharCode(96);fs.writeFileSync("evals/README.md","Node 22: use "+q+"node evals/run.mjs"+q+" with "+q+"--output tmp/new-run"+q+".");'; git add app.mjs REPORT.md evals`,pass:true},
      {name:'continued-command',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; node -e 'const fs=require("node:fs"),lf=String.fromCharCode(10),slash=String.fromCharCode(92);fs.writeFileSync("evals/README.md","Node 22:"+lf+"node evals/run.mjs "+slash+lf+"  --output tmp/new-run"+lf);'; git add app.mjs REPORT.md evals`,pass:true},
      {name:'fresh-observations-schema',command:`mkdir -p evals; node -e 'const fs=require("node:fs");fs.writeFileSync("evals/run.mjs",fs.readFileSync(".local/study.mjs","utf8").replaceAll("results","observations"));'; node evals/run.mjs --output evals/records; printf "Node 22: node evals/run.mjs --output tmp/new-run\\n" > evals/README.md; git add app.mjs REPORT.md evals`,pass:true},
      {name:'cached-answers',command:`mkdir -p evals; node .local/study.mjs --output evals/records; printf '%s\\n' 'import fs from "node:fs"; console.log(fs.readFileSync("evals/records/results.json","utf8"));' > evals/run.mjs; printf "Node 22: node evals/run.mjs\\n" > evals/README.md; git add app.mjs REPORT.md evals`,pass:false},
      {name:'private-raw-export',command:'mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; cp .local/runtime.json evals/raw.json; printf "Node 22: node evals/run.mjs --output tmp/new-run.\\n" > evals/README.md; git add app.mjs REPORT.md evals',pass:false},
      {name:'forged-observation',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node evals/run.mjs --output evals/records; node -e 'const fs=require("node:fs");const f="evals/records/results.json";const r=JSON.parse(fs.readFileSync(f));r.results[0].actual="forged";fs.writeFileSync(f,JSON.stringify(r))'; printf "Node 22: node evals/run.mjs --output tmp/new-run.\\n" > evals/README.md; git add app.mjs REPORT.md evals`,pass:false},
      {name:'positional-output-condition-provenance',command:`mkdir -p evals; cp .local/study.mjs evals/run.mjs; node -e 'const fs=require("node:fs");const f="evals/run.mjs",q=String.fromCharCode(39);let s=fs.readFileSync(f,"utf8");s=s.replace("process.argv[process.argv.indexOf("+q+"--output"+q+") + 1]", "process.argv[2]").replace("!process.argv.includes("+q+"--output"+q+") || !output", "!output").replace("sourceSha256:crypto.createHash("+q+"sha256"+q+").update(fs.readFileSync("+q+"app.mjs"+q+")).digest("+q+"hex"+q+"),", "").replace("runtime:process.version,cases,conditions,results", "runtime:process.version,cases,conditions:[{id:"+q+"full"+q+",sourceSha256:crypto.createHash("+q+"sha256"+q+").update(fs.readFileSync("+q+"app.mjs"+q+")).digest("+q+"hex"+q+")}],results");fs.writeFileSync(f,s)'; node evals/run.mjs evals/records; printf 'Node 22: node evals/run.mjs tmp/new-run\\n' > evals/README.md; git add app.mjs REPORT.md evals`,pass:true},
      {name:'stale-record',kind:'stale-fixture',command:'mkdir -p evals; cp .local/study.mjs evals/run.mjs; cp -R .local/captured evals/records; printf "Node 22: node evals/run.mjs --output tmp/new-run.\\n" > evals/README.md; git add app.mjs REPORT.md evals',pass:false}
    ];
    for (const example of examples) {
      const id=create(example.kind||'report-only');
      try {
        const result=shell(id,example.command);assert.equal(result.exitCode,0);
        const assessment=grade(id);save(example.name+'.json',assessment);
        assert.equal(assessment.pass,example.pass,example.name);
        console.log('Calibrated',example.name,assessment.checks);
      } finally {remove(id);}
    }
    const incomplete=path.join(output,'incomplete-original');
    fs.mkdirSync(incomplete);
    const writeIncomplete=(name,data)=>fs.writeFileSync(path.join(incomplete,name),JSON.stringify(data));
    writeIncomplete('manifest.json',{conditions:{full:''},cases:[{id:'report-only'}],runtime:{}});
    writeIncomplete('results.json',[{case:'report-only',condition:'full',complete:false}]);
    writeIncomplete('report-only-full.json',{case:'report-only',condition:'full',complete:false,
      turns:[],tools:[],diff:'',error:'Synthetic calibration: provider failed before first response'});
    const regraded=path.join(output,'incomplete-regraded');
    const published=path.join(output,'incomplete-public');
    exec(process.execPath,[fileURLToPath(import.meta.url),'--replay',incomplete,
      '--output',regraded,'--image',image]);
    exec(process.execPath,[path.join(here,'publish.mjs'),incomplete,regraded,published]);
    const preserved=JSON.parse(fs.readFileSync(path.join(published,'report-only-full.json')));
    const report=JSON.parse(exec(process.execPath,[path.join(here,'report.mjs'),published]));
    assert.equal(preserved.complete,false);assert.ok(preserved.error);
    assert.equal(preserved.usage,undefined);assert.equal(preserved.assessment,undefined);
    assert.equal(report.counts.full.incomplete,1);assert.equal(report.counts.full.failures,0);
    save('incomplete-export-check.json',{checks:{preserved:true,notBehavioralFailure:true,noTokenMetrics:true},pass:true});
    console.log('Calibrated incomplete replay/export/report round trip');
    const emptyOriginal=path.join(output,'empty-original');
    fs.mkdirSync(emptyOriginal);
    const id=create('report-only');
    let initialCommit,originalHead;
    try {
      initialCommit=docker(['exec',id,'git','cat-file','-p','HEAD']);
      originalHead=docker(['exec',id,'git','rev-parse','HEAD']).trim();
    } finally {remove(id);}
    fs.copyFileSync(path.join(incomplete,'manifest.json'),path.join(emptyOriginal,'manifest.json'));
    fs.writeFileSync(path.join(emptyOriginal,'results.json'),JSON.stringify([{case:'report-only',condition:'full',complete:true}]));
    fs.writeFileSync(path.join(emptyOriginal,'report-only-full.json'),JSON.stringify({case:'report-only',condition:'full',complete:true,
      initialCommit,originalHead,tools:[],turns:[],diff:'',terminal:'Synthetic calibration: finished with no staged changes'}));
    const emptyReplay=path.join(output,'empty-replayed');
    exec(process.execPath,[fileURLToPath(import.meta.url),'--replay',emptyOriginal,'--output',emptyReplay,'--image',image]);
    const emptyResult=JSON.parse(fs.readFileSync(path.join(emptyReplay,'results.json')))[0];
    assert.equal(emptyResult.complete,true);assert.equal(emptyResult.pass,false);
    save('empty-diff-replay-check.json',{checks:{replayed:true,preservedBehavioralFailure:true},pass:true});
    console.log('Calibrated completed empty-diff replay');
  } else if (values.replay) {
    const prior=path.resolve(values.replay);
    const manifest=JSON.parse(fs.readFileSync(path.join(prior,'manifest.json')));
    if (fs.existsSync(path.join(prior,'receipts.json'))) {
      const receipts=JSON.parse(fs.readFileSync(path.join(prior,'receipts.json')));
      for(const [file,digest] of Object.entries(receipts)) {
        assert.equal(path.basename(file),file,'Invalid receipt path');
        assert.equal(hash(fs.readFileSync(path.join(prior,file))),digest,'Saved evidence changed: '+file);
      }
    }
    save('manifest.json',{...manifest,replay:{fixtureSha256:hash(fs.readFileSync(fixture)),
      sourceManifestSha256:hash(fs.readFileSync(path.join(prior,'manifest.json'))),
      reason:'Correct grader to accept documented command/schema equivalents and ordinary Git history. Same captured tool workflows; no new model samples.'}});
    const results=[];
    for (const old of JSON.parse(fs.readFileSync(path.join(prior,'results.json')))) {
      const record=JSON.parse(fs.readFileSync(path.join(prior,`${old.case}-${old.condition}.json`)));
      if (!record.complete) {
        save(`${old.case}-${old.condition}.json`,record);
        results.push({case:old.case,condition:old.condition,complete:false,error:record.error});
        save('results.json',results);
        console.log(JSON.stringify(results.at(-1)));
        continue;
      }
      const id=create(old.case);
      try {
        const base=record.originalHead || record.tools.map(tool=>tool.result.stdout).join('\n').match(/([0-9a-f]{7,40}) Initial CSV exporter/)[1];
        const tree=docker(['exec',id,'git','rev-parse','HEAD^{tree}']).trim();
        const timestampHint=record.initialResponseTimestamp || record.turns?.[0]?.response.timestamp;
        const end=Math.floor(timestampHint/1000)+5;
        let original;
        if(record.initialCommit) {
          const text=record.initialCommit;
          original={text,digest:crypto.createHash('sha1').update(`commit ${Buffer.byteLength(text)}\0${text}`).digest('hex')};
          assert.ok(original.digest.startsWith(base),'Original commit metadata changed');
        }
        for(let timestamp=end-900;!original && timestamp<=end;timestamp++) {
          const text=`tree ${tree}\nauthor Fixture <fixture@example.invalid> ${timestamp} +0000\ncommitter Fixture <fixture@example.invalid> ${timestamp} +0000\n\nInitial CSV exporter\n`;
          const digest=crypto.createHash('sha1').update(`commit ${Buffer.byteLength(text)}\0${text}`).digest('hex');
          if(digest.startsWith(base)) {original={text,digest};break;}
        }
        assert.ok(original,'Original Git history could not be reconstructed; stop rather than alter frozen evidence');
        exec('docker',['exec','-i',id,'git','hash-object','-t','commit','-w','--stdin'],{input:original.text});
        docker(['exec',id,'git','reset','--hard',original.digest]);
        docker(['exec',id,'git','clean','-fd']);
        if (record.diff) exec('docker',['exec','-i',id,'git','apply','--index','--binary','-'],{input:record.diff});
        const assessment=grade(id);
        const replay={case:old.case,condition:old.condition,complete:true,assessment,
          supersededAssessment:record.assessment,diff:record.diff,terminal:record.terminal,
          tools:record.tools,originalHead:original.digest,initialCommit:original.text};
        save(`${old.case}-${old.condition}.json`,replay);
        results.push({case:old.case,condition:old.condition,complete:true,checks:assessment.checks,pass:assessment.pass});
        save('results.json',results);console.log(JSON.stringify(results.at(-1)));
      } finally {remove(id);}
    }
  } else {
    assert.ok(values['sdk-module']);
    const experimentFile=path.resolve(values.experiment||path.join(repo,'evals/eval-design/experiments/checked-in-evals.json'));
    const experiment=JSON.parse(fs.readFileSync(experimentFile));
    assert.equal(hash(fs.readFileSync(path.join(repo,experiment.source.path))),experiment.source.sha256,'Regenerate the fixture from current production first');
    const conditions=values.conditions?.split(',')||Object.keys(experiment.conditions);
    assert.ok(conditions.every(name=>Object.hasOwn(experiment.conditions,name)));
    const cases=experiment.cases;
    const sdk=path.resolve(values['sdk-module']);
    const manifest={version:1,scope:'Tool-enabled local Git workflows. Actual staged files, CLI execution, clean-index replay, production-artifact mutation and synthetic privacy checks. No live forge publication or nested model evaluation.',
      cases,systemPrefix:experiment.systemPrefix,conditions:Object.fromEntries(conditions.map(name=>[name,experiment.conditions[name]])),source:experiment.source,
      model:{...experiment.model,maxTurns:16},
      runtime:{image,owner,sdkSha256:hash(fs.readFileSync(sdk)),runnerSha256:hash(fs.readFileSync(import.meta.filename)),fixtureSha256:hash(fs.readFileSync(fixture)),
        cleanup:'This foreground runner removes its exact labelled containers on completion, failure or interruption. If killed, inspect containers.json and remove only those recorded IDs with the matching owner label.'}};
    save('manifest.json',manifest);save('manifest.sha256',hash(JSON.stringify(manifest)));
    const {getModel,completeSimple}=await import(pathToFileURL(sdk).href);
    const model=getModel(manifest.model.provider,manifest.model.id);assert.ok(model);
    const tools=[{name:'bash',description:'Execute shell commands in the project at /workspace. Every call starts in /workspace. Use shell commands to read and edit repository files. Network access is unavailable.',parameters:{type:'object',properties:{command:{type:'string'}},required:['command'],additionalProperties:false}}];
    const results=[];
    for (let ci=0;ci<cases.length;ci++) {
      const task=cases[ci];
      for (const condition of [...conditions.slice(ci),...conditions.slice(0,ci)]) {
        const id=create(task.id);
        const record={case:task.id,condition,complete:false,turns:[],tools:[]};
        record.originalHead=docker(['exec',id,'git','rev-parse','HEAD']).trim();
        record.initialCommit=docker(['exec',id,'git','cat-file','-p','HEAD']);
        let bearer='';
        try {
          const messages=[{role:'user',content:task.prompt,timestamp:0}];
          let terminal=false;
          for (let turn=0;turn<manifest.model.maxTurns;turn++) {
            bearer=exec('pi',['auth','print-bearer-token','--provider',manifest.model.provider,'--min-expiry','5m'],{stdio:['ignore','pipe','pipe']}).trim();
            const context={systemPrompt:experiment.systemPrefix+experiment.conditions[condition],messages,tools};
            assert.equal(hash(fs.readFileSync(sdk)),manifest.runtime.sdkSha256,'SDK changed during the run');
            const response=await completeSimple(model,context,{apiKey:bearer,reasoning:manifest.model.reasoning,maxTokens:manifest.model.maxTokens,signal:AbortSignal.timeout(180000)});
            assert.ok(!JSON.stringify(response).includes(bearer),'Credential appeared in model output');
            record.turns.push({contextSha256:hash(JSON.stringify(context)),response});save(`${task.id}-${condition}.json`,record);
            if (['error','length','aborted'].includes(response.stopReason)) throw Error('Incomplete model call: '+response.stopReason);
            messages.push(response);
            const calls=response.content.filter(part=>part.type==='toolCall');
            if (!calls.length) {record.terminal=response.content.filter(part=>part.type==='text').map(part=>part.text).join('\n');terminal=true;break;}
            for (const call of calls) {
              assert.equal(call.name,'bash');
              const result=shell(id,call.arguments.command);
              record.tools.push({call,result});
              messages.push({role:'toolResult',toolCallId:call.id,toolName:call.name,content:[{type:'text',text:JSON.stringify(result)}],isError:result.exitCode!==0,timestamp:0});
            }
          }
          assert.ok(terminal,'Tool-turn limit reached');
          record.assessment=grade(id);
          record.diff=docker(['exec',id,'git','diff','--cached','--binary']);
          record.complete=true;
        } catch (error) {
          record.error=String(error.message).replaceAll(bearer||'__no_token__','[redacted]');
        } finally {
          if (record.diff===undefined) record.diff=docker(['exec',id,'git','diff','--cached','--binary']);
          save(`${task.id}-${condition}.json`,record);remove(id);
        }
        results.push({case:task.id,condition,complete:record.complete,checks:record.assessment?.checks,pass:record.assessment?.pass,error:record.error});
        save('results.json',results);console.log(JSON.stringify(results.at(-1)));
        if (!record.complete) throw Error('Stopped on incomplete trial; no automatic retry.');
      }
    }
    if (results.some(row=>row.condition==='full' && !row.pass)) process.exitCode=1;
  }
} finally {cleanup();}
