import fs from 'node:fs';
import { loadDefinition } from './definition.mjs';

export default async function (pi) {
  const definition = await loadDefinition(process.env.SESSION_NAMING_EVAL_REF);
  const descriptionFile = process.env.SESSION_NAMING_EVAL_DESCRIPTION_FILE;
  pi.registerTool({
    ...definition,
    description: descriptionFile ? fs.readFileSync(descriptionFile, 'utf8') : definition.description,
    async execute(_id, { name }) {
      return {
        content: [{ type: 'text', text: `Recorded name: ${name}` }],
        details: { name },
        terminate: true,
      };
    },
  });
}
