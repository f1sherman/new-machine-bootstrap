"""Grade the submission recorder, not the agent's draft or final answer."""
import json
from pathlib import Path
import re
import subprocess

records = json.loads(Path('/workspace/submissions.json').read_text())
record = records[0] if len(records) == 1 else {}
# Read the target commit from the fresh verifier image, not from candidate logs.
head = subprocess.check_output(['git', '-c', 'safe.directory=/workspace/project',
                                '-C', '/workspace/project', 'rev-parse', 'HEAD'],
                               text=True).strip()
submitted = (record.get('base'), record.get('head'), record.get('commit'), record.get('url')) == (
    'main', 'longer-retry-delay', head, 'https://pr.example.invalid/1')
title = record.get('title', '')
body = record.get('body', '')
checks = {'submitted': int(submitted),
          'descriptive_title': int(submitted and bool(re.search(r'\bretr(?:y|ies)\b', title, re.I))),
          'describes_change': int(submitted and bool(
              re.search(r'\b30[ -]+seconds?\b', body, re.I) and
              re.search(r'\b(?:5|five)(?:[ -]+seconds?\b|\s+to\s+30[ -]+seconds?\b)', body, re.I)))}
Path('/logs/verifier/reward.json').write_text(json.dumps(checks) + '\n')
