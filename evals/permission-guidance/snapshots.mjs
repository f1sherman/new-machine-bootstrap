import fs from 'node:fs';
import path from 'node:path';

// Observe native tool boundaries without adding policy or changing tool results.
export default function (pi) {
  const log = '/logs/agent/permission-snapshots.jsonl';
  const watched = JSON.parse(fs.readFileSync('/opt/eval/watched.json', 'utf8'));
  function snapshot(phase, toolCallId) {
    const files = Object.fromEntries(watched.map(file => {
      const target = path.join('/workspace', file);
      return [file, fs.existsSync(target) ? fs.readFileSync(target, 'utf8') : null];
    }));
    fs.appendFileSync(log, JSON.stringify({ phase, toolCallId, files }) + '\n');
  }
  pi.on('session_start', () => {
    fs.writeFileSync(log, '');
    snapshot('session_start');
  });
  pi.on('tool_result', event => snapshot('tool_result', event.toolCallId));
  pi.on('agent_settled', () => snapshot('agent_settled'));
}
