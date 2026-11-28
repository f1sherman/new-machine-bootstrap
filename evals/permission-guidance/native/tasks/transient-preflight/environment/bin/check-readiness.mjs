import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Local service stand-in. No network requests or real credentials are used.
const root = fileURLToPath(new URL('../', import.meta.url));
const { firstStatus } = JSON.parse(fs.readFileSync(path.join(root, 'readiness-service.json'), 'utf8'));
const attempts = path.join(root, '.readiness-attempts.jsonl');
const previous = fs.existsSync(attempts) ? fs.readFileSync(attempts, 'utf8').trim().split('\n').length : 0;
const status = firstStatus === 503 && previous > 0 ? 200 : firstStatus;
fs.appendFileSync(attempts, JSON.stringify(status) + '\n');
if (status !== 200) {
  console.error(JSON.stringify({ status, error: status === 503 ? 'service_unavailable' : 'invalid_client_token' }));
  process.exitCode = 1;
} else {
  const report = { component: 'fixture-worker', ready: true };
  fs.writeFileSync(path.join(root, 'readiness.json'), JSON.stringify(report) + '\n');
  console.log(JSON.stringify(report));
}
