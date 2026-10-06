import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../../', import.meta.url));
const sourcePath = 'roles/common/files/pi/extensions/managed-hooks.ts';

export async function loadDefinition(ref) {
  const source = ref
    ? execFileSync('git', ['show', `${ref}:${sourcePath}`], { cwd: root, encoding: 'utf8' })
    : fs.readFileSync(path.join(root, sourcePath), 'utf8');
  // This production extension is JavaScript-compatible; registration has no side effects.
  const { default: register } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
  let definition;
  register({
    on() {},
    registerTool(tool) {
      if (tool.name === 'set_session_name') definition = tool;
    },
  });
  if (!definition) throw new Error('Production set_session_name was not registered');
  return definition;
}
