import path from 'node:path';

export function jobArguments(manifest, output, variant, item, attempt, network = []) {
  const args = ['run', '--path', path.join(output, 'tasks', variant.id, item.id), '--agent', manifest.agent, '--model', manifest.model,
    '--agent-kwarg', `version=${manifest.piVersion}`, '--agent-kwarg', `thinking=${manifest.thinking}`,
    '--agent-env', 'PI_TELEMETRY=0', '--agent-env', 'PI_SKIP_VERSION_CHECK=1', '--n-attempts', '1', '--n-concurrent', '1',
    '--job-name', `${item.id}-${attempt}`, '--jobs-dir', path.join(output, 'jobs', variant.id), ...network];
  if (manifest.resume) args.push('--resume-trajectory', '--agent-env', `PI_MANAGED_CHILD_MODEL=${manifest.model}`);
  if (manifest.verifier) args.push('--verifier', manifest.verifier, '--agent-kwarg', `system_prompt=${JSON.stringify(variant.systemPrompt)}`);
  return args;
}
