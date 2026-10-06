import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { loadDefinition } from '../session-naming/definition.mjs';

export const root = fileURLToPath(new URL('../../', import.meta.url));
export const readJSON = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const write = (file, text) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text); };
export function select(items, csv, defaults = items.map(item => item.id)) {
  const ids = csv ? csv.split(',') : defaults;
  if (!ids.length || new Set(ids).size !== ids.length) throw Error('Select distinct cases/conditions');
  return ids.map(id => { const item = items.find(item => item.id === id); if (!item) throw Error(`Unknown selection: ${id}`); return item; });
}

export async function prepare(suite, options, output) {
  if (suite === 'command-guidance') {
    if (options.ablate || options['compare-ref']) throw Error('Command suite has guidance/empty conditions; naming ablation flags do not apply');
    const directory = path.join(root, 'evals/command-guidance');
    const cases = select(readJSON(path.join(directory, 'cases.json')), options.cases);
    const variants = select(['guidance', 'none'].map(id => ({ id, primary: id === 'guidance',
      systemPrompt: 'You are a coding assistant. Give terminal commands for a user to copy and paste.\n\n' + fs.readFileSync(path.join(directory, 'variants', `${id}.md`), 'utf8') })), options.conditions);
    for (const variant of variants) for (const item of cases) {
      const task = path.join(output, 'tasks', variant.id, item.id);
      const prompt = item.prompt + '\nReturn only one shell code block with all required commands. Do not execute anything.';
      write(path.join(task, 'instruction.md'), prompt);
      write(path.join(task, 'task.toml'), 'schema_version = "1.3"\n[environment]\nbuild_timeout_sec = 600\ncpus = 1\nmemory_mb = 1024\n[agent]\ntimeout_sec = 180\n[verifier]\ntimeout_sec = 30\n');
      write(path.join(task, 'environment/Dockerfile'), fs.readFileSync(path.join(root, 'evals/harbor/command.Dockerfile')));
      write(path.join(task, 'tests/test.sh'), '#!/bin/sh\nprintf "%s\\n" "This task requires the macOS host verifier." >&2\nexit 1\n');
      write(path.join(task, 'tests/case.json'), JSON.stringify({ test_case: item, settings: {
        provider: options.model.split('/')[0], model: options.model.split('/')[1], thinking: 'medium', system_prompt: variant.systemPrompt, prompt,
      } }, null, 2) + '\n');
    }
    return { suite, thinking: 'medium', agent: 'evals.harbor.prompt_agent:PromptOnlyPi',
      verifier: 'evals.harbor.command_verifier:MacOSCommandVerifier', resume: false,
      variants, cases: cases.map(({ id }) => ({ id, steps: [] })) };
  }
  if (suite !== 'session-naming') throw Error('Select --suite command-guidance or session-naming');
  const cases = select([
    { id: 'incidental-bug-report', steps: ['repair-restoration', 'report-incidental-bug', 'continue-restoration', 'explicit-rename', 'change-goal'] },
    { id: 'incidental-monitor-report', steps: ['repair-restoration', 'report-incidental-bug', 'continue-restoration'] },
  ], options.cases, ['incidental-bug-report']);
  const definition = await loadDefinition();
  const variants = [{ id: 'current', primary: true, description: definition.description }];
  if (options['compare-ref']) {
    const ref = execFileSync('git', ['rev-parse', '--verify', '--end-of-options', `${options['compare-ref']}^{commit}`], { cwd: root, encoding: 'utf8' }).trim();
    variants.unshift({ id: 'baseline', primary: false, ref, description: (await loadDefinition(ref)).description });
  }
  if (options.ablate) {
    const sections = definition.description.split('\n\n');
    if (sections.length !== 3) throw Error('Expected three naming-description sections');
    variants.push(
      { id: 'without-call-threshold', primary: false, description: sections.slice(1).join('\n\n') },
      { id: 'without-side-task-context', primary: false, description: [sections[0], sections[2]].join('\n\n') },
      { id: 'without-name-construction', primary: false, description: sections.slice(0, 2).join('\n\n') },
      { id: 'without-description', primary: false, description: '' },
    );
  }
  const chosen = select(variants, options.conditions);
  for (const variant of chosen) for (const item of cases) {
    const task = path.join(output, 'tasks', variant.id, item.id);
    fs.cpSync(path.join(root, 'evals/session-naming/tasks/incidental-bug-report'), task,
      { recursive: true, filter: source => !source.includes('__pycache__') });
    if (item.id === 'incidental-monitor-report') {
      fs.renameSync(path.join(task, 'tests/verify.py'), path.join(task, 'tests/base_verify.py'));
      fs.cpSync(path.join(root, 'evals/session-naming/tasks', item.id), task,
        { recursive: true, filter: source => !source.includes('__pycache__') });
    }
    fs.mkdirSync(path.join(task, 'environment/project/tests'), { recursive: true });
    fs.copyFileSync(path.join(task, 'tests/restoration.rb'), path.join(task, 'environment/project/tests/restoration.rb'));
    fs.copyFileSync(path.join(root, 'roles/common/files/pi/extensions/managed-hooks.ts'), path.join(task, 'environment/managed-hooks.ts'));
    fs.copyFileSync(path.join(root, 'roles/common/files/pi/AGENTS.md.d/00-base.md'), path.join(task, 'environment/AGENTS.md'));
    write(path.join(task, 'environment/description.txt'), variant.description);
  }
  return { suite, thinking: 'low', agent: 'pi', resume: true, variants: chosen, cases };
}

export function findTrials(directory) {
  const file = path.join(directory, 'result.json');
  if (fs.existsSync(file)) {
    const result = readJSON(file);
    if (typeof result.task_name === 'string') return [directory];
    if (!Number.isInteger(result.n_total_trials) || typeof result.stats !== 'object') throw Error(`Invalid Harbor result: ${file}`);
    // Harbor stores both job summaries and individual trial results under this name.
  }
  return fs.readdirSync(directory, { withFileTypes: true }).filter(item => item.isDirectory())
    .flatMap(item => findTrials(path.join(directory, item.name)));
}

export function completedResult(trial) {
  const result = readJSON(path.join(trial, 'result.json'));
  const error = result.exception_info ?? result.step_results?.find(step => step.exception_info)?.exception_info;
  if (error) throw Error(`Harbor infrastructure error in ${trial}: ${error.exception_message}`);
  return result;
}

export function collect(manifest, output, variant) {
  const job = path.join(output, 'jobs', variant.id);
  const rows = findTrials(job).map(trial => {
    const result = completedResult(trial);
    const item = manifest.cases.find(item => item.id === result.task_name);
    if (!item) throw Error(`Unexpected task ${result.task_name}`);
    let checks, usage, evidence;
    if (manifest.suite === 'command-guidance') {
      const assessment = readJSON(path.join(trial, 'verifier/assessment.json'));
      const reward = readJSON(path.join(trial, 'verifier/reward.json'));
      if (assessment.infrastructure_error || typeof assessment.grade?.pass !== 'boolean') throw Error('Invalid command assessment');
      checks = { combined: assessment.grade.pass, functional: reward.functional === 1, formatPolicy: reward.format_policy === 1 };
      if (reward.reward !== Number(checks.combined)) throw Error('Command reward disagrees with assessment');
      usage = assessment.usage;
      evidence = { assessment, path: trial };
    } else {
      if (result.step_results?.map(step => step.step_name).join(',') !== item.steps.join(',')) throw Error(`Incomplete workflow in ${trial}`);
      const steps = result.step_results.map(step => {
        const directory = path.join(trial, 'steps', step.step_name);
        const assessment = readJSON(path.join(directory, 'verifier/assessment.json'));
        const reward = readJSON(path.join(directory, 'verifier/reward.json'));
        if (typeof assessment.naming !== 'boolean' || typeof assessment.task !== 'boolean'
          || reward.naming !== Number(assessment.naming) || reward.task !== Number(assessment.task)
          || reward.reward !== Number(assessment.naming && assessment.task)) throw Error('Invalid naming rewards');
        return { step: step.step_name, ...assessment, path: directory };
      });
      if (new Set(steps.map(step => step.sessionId)).size !== 1) throw Error('Session changed between steps');
      checks = { naming: steps.every(step => step.naming), task: steps.every(step => step.task) };
      usage = Object.fromEntries(['input', 'output', 'cacheRead', 'cacheWrite'].map(key => [key, steps.reduce((sum, step) => sum + step.usage[key], 0)]));
      evidence = { steps, path: trial };
    }
    if (!usage || !['input', 'output'].every(key => Number.isFinite(usage[key]) && usage[key] >= 0)) throw Error('Missing usage');
    return { condition: variant.id, case: item.id, trial: path.relative(job, trial), primary: variant.primary, checks,
      passed: Object.values(checks).every(Boolean), mainAgentUsage: usage, ...evidence };
  });
  for (const item of manifest.cases) if (rows.filter(row => row.case === item.id).length !== manifest.trials) throw Error(`Missing/extra trials for ${variant.id}/${item.id}`);
  return rows;
}
