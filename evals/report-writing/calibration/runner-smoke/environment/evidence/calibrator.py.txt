"""Exercise the production test entry point against actual fixture state."""
import json
from pathlib import Path
import subprocess

repo = '/workspace/project'
record = Path('/workspace/submissions.json')
reward = Path('/logs/verifier/reward.json')
reward.parent.mkdir(parents=True, exist_ok=True)
body = Path('/tmp/pr.md')


def grade():
    reward.unlink(missing_ok=True)
    subprocess.run(['sh', '/tests/test.sh'], check=True)
    return json.loads(reward.read_text())


subprocess.run(['runuser', '-u', 'worker', '--', 'git', '-C', repo,
                'push', 'origin', 'longer-retry-delay'], check=True, capture_output=True)
results = {}
body.write_text('Failed deliveries wait 30 seconds instead of 5 seconds before retry.\n')
results['draft_only'] = grade()
assert results['draft_only'] == {'submitted': 0, 'descriptive_title': 0, 'describes_change': 0}
for label, title, text in (
    ('submitted', 'Increase retry delay', body.read_text()),
    ('equivalent', 'Wait longer between retries', 'Switch from five seconds to 30 seconds.\n'),
):
    record.write_text('[]\n')
    body.write_text(text)
    subprocess.run(['runuser', '-u', 'worker', '--', 'fixture-pr', '--base', 'main',
                    '--head', 'longer-retry-delay', '--title', title, '--body-file', str(body)],
                   check=True, capture_output=True)
    accepted = json.loads(record.read_text())[0]
    assert (accepted['title'], accepted['body']) == (title, text)
    results[label] = grade()
    assert results[label] == {'submitted': 1, 'descriptive_title': 1, 'describes_change': 1}
print(json.dumps(results))
