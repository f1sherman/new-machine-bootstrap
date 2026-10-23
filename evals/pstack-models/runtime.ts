// Inert native-harness replay. No candidate command or delegate is executed.
import fs from 'node:fs';
import path from 'node:path';
import { Type } from '@earendil-works/pi-ai';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

export default function(pi: ExtensionAPI) {
  const fixture = JSON.parse(fs.readFileSync(process.env.PSTACK_EVAL_INPUT!, 'utf8'));
  const log = (tool: string, args: unknown) => fs.appendFileSync(process.env.PSTACK_EVAL_CALLS!, JSON.stringify({tool,args})+'\n');
  const result = (value: unknown) => ({content:[{type:'text' as const,text:typeof value === 'string' ? value : JSON.stringify(value)}],details:undefined});
  pi.registerTool({name:'read',label:'Read',description:'Read file contents.',parameters:Type.Object({path:Type.String(),offset:Type.Optional(Type.Number()),limit:Type.Optional(Type.Number())}),
    async execute(_id,args) {
      log('read',args);
      const file = fixture.files[args.path] ?? fixture.files[path.basename(args.path)];
      if (file === undefined) throw new Error('File not found');
      return result(file);
    }});
  pi.registerTool({name:'write',label:'Write',description:'Write a file.',parameters:Type.Object({path:Type.String(),content:Type.String()}),
    async execute(_id,args) { log('write',args); fixture.files[args.path]=args.content; return result('Written.'); }});
  pi.registerTool({name:'bash',label:'Bash',description:'Execute a shell command.',parameters:Type.Object({command:Type.String(),timeout:Type.Optional(Type.Number())}),
    async execute(_id,args) {
      log('bash',args);
      if (args.command.includes('models.rb show')) return result({status:fixture.profile ? 'configured':'unconfigured',profile:fixture.profile});
      if (args.command.includes('models.rb roles')) return result(fixture.roles);
      if (args.command.includes('models.rb resolve')) return result(fixture.resolution);
      if (args.command.includes('models.rb save')) return result({status:'saved'});
      if (args.command.includes('--list-models')) return result(fixture.catalog);
      if (args.command.includes('test ') || args.command.includes('ls ')) return result('present');
      throw new Error('Command unavailable in this environment');
    }});
  pi.registerTool({name:'subagent',label:'Subagent',description:'Run a native agent, or discover agents and models.',parameters:Type.Object({action:Type.Optional(Type.String()),agent:Type.Optional(Type.String()),task:Type.Optional(Type.String()),model:Type.Optional(Type.String()),context:Type.Optional(Type.String()),async:Type.Optional(Type.Boolean())}),
    async execute(_id,args) {
      log('subagent',args);
      if (args.action === 'models') return result(fixture.catalog);
      if (args.action === 'list') return result({agents:[{name:'reviewer',readOnly:true,model:'inherit-parent'}]});
      if (args.action || !args.agent) throw new Error('Unsupported subagent action');
      return result({status:'completed',output:'The linker compares resolved managed symlinks and removes stale links only inside its managed source root.'});
    }});
}
