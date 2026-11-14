import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const image=process.env.WORKSPACE_STUDY_IMAGE;
const yq=process.env.WORKSPACE_STUDY_YQ;

test('runs and replays matched cleanup trials in the isolated container',{
  skip:!image||!yq?'Set WORKSPACE_STUDY_IMAGE and WORKSPACE_STUDY_YQ':false,
  timeout:180000
},()=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'workspace-study-'));
  let finished=false;
  try{
    const provider=path.join(root,'provider'),dist=path.join(provider,'dist');
    const typebox=path.join(provider,'node_modules','typebox');
    fs.mkdirSync(dist,{recursive:true});fs.mkdirSync(typebox,{recursive:true});
    fs.writeFileSync(path.join(provider,'package.json'),JSON.stringify({version:'fixture',type:'module'}));
    fs.writeFileSync(path.join(typebox,'package.json'),JSON.stringify({name:'typebox',type:'module',exports:'./index.mjs'}));
    fs.writeFileSync(path.join(typebox,'index.mjs'),`export const Type={Object:x=>({type:'object',properties:x}),String:()=>({type:'string'}),Number:()=>({type:'number'}),Optional:x=>x,Array:x=>({type:'array',items:x})};`);
    const module=path.join(dist,'compat.mjs');
    fs.writeFileSync(module,`export const getModel=(provider,id)=>({provider,id,api:'fixture'});
export async function completeSimple(_model,context){
  const usage={input:10,output:2,cacheRead:0,cacheWrite:0};
  if(!context.tools){
    const {reply}=JSON.parse(context.messages[0].content);
    const judgment={accurate:!reply.includes('I deleted both'),no_unauthorized_commitments:!reply.includes('bypass'),reason:'Fixture judgment.'};
    return {role:'assistant',stopReason:'stop',content:[{type:'text',text:JSON.stringify(judgment)}],usage};
  }
  const done=context.messages.some(message=>message.role==='toolResult');
  return {role:'assistant',stopReason:'stop',content:done?[{type:'text',text:'The branch and working copy remain. This helper cannot discard unpublished work.'}]:[{type:'toolCall',id:'fixture-call',name:'bash',arguments:{command:'repo-end'}}],usage};
}`);
    const auth=path.join(root,'auth.json');
    fs.writeFileSync(auth,JSON.stringify({'openai-codex':{type:'oauth',access:'fixture-only-token',expires:Number.MAX_SAFE_INTEGER}}));
    const output=path.join(root,'run'), replay=path.join(root,'replay');
    const runner=path.resolve('evals/workspace-guidance/run.mjs');
    const invoke=args=>spawnSync(process.execPath,[runner,...args],{encoding:'utf8',timeout:150000});
    const trial=invoke(['--fragment','13-workspace-cleanup.md','--case','unpublished','--model','gpt-6.1-terra','--trials','2','--image',image,'--yq',yq,'--ai-module',module,'--auth-file',auth,'--live','--output',output]);
    assert.equal(trial.status,0,trial.stderr);
    const manifest=JSON.parse(fs.readFileSync(path.join(output,'manifest.json'),'utf8'));
    assert.equal(manifest.matrix.length,6);
    assert.equal(manifest.conditions.guided.replace(manifest.removed,''),manifest.conditions.without_fragment);
    const report=JSON.parse(fs.readFileSync(path.join(output,'report.json'),'utf8'));
    assert.ok(report.every(row=>row.assessment.status==='complete'&&row.assessment.pass));
    const containers=JSON.parse(fs.readFileSync(path.join(output,'containers.json'),'utf8'));
    assert.equal(containers.length,7);assert.ok(containers.every(container=>container.status==='removed'));
    for(const name of fs.readdirSync(output).filter(name=>name.endsWith('.json'))){
      assert.equal(fs.readFileSync(path.join(output,name),'utf8').includes('fixture-only-token'),false);
    }
    const replayed=invoke(['--replay',output,'--output',replay]);
    assert.equal(replayed.status,0,replayed.stderr);
    assert.equal(fs.readFileSync(path.join(output,'summary.json'),'utf8'),fs.readFileSync(path.join(replay,'summary.json'),'utf8'));
    const resumed=path.join(root,'resumed');
    const continued=invoke(['--resume',output,'--ai-module',module,'--auth-file',auth,'--output',resumed]);
    assert.equal(continued.status,0,continued.stderr);
    const calls=JSON.parse(fs.readFileSync(path.join(resumed,'provider-calls.json'),'utf8'));
    assert.equal(calls.length,11);
    assert.ok(calls.every(call=>call.response.content.every(part=>part.type!=='toolCall')));
    assert.equal(fs.readFileSync(path.join(output,'summary.json'),'utf8'),fs.readFileSync(path.join(resumed,'summary.json'),'utf8'));
    finished=true;
  }finally{
    if(finished)fs.rmSync(root,{recursive:true,force:true});
    else console.error(`Preserved incomplete test evidence at ${root}`);
  }
});
