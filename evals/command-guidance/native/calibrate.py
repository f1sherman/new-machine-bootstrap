"""Study-specific constructions; the shared launcher owns container setup."""
import json
from pathlib import Path
import subprocess
import sys

from command_sandbox import calibrate_boundary
from verify import grade


def block(command):
    return '```bash\n' + command + '\n```'


boundary = calibrate_boundary()
name = sys.argv[1]
case = json.loads(Path('/tests/case.json').read_text())
correct = {
    'path-spaces': 'f="/home/eval/Library/Application Support"\nf="$f/Remote Environment/production/service settings.yaml"\ncat "$f"',
    'mixed-arguments': 'f="/home/eval/.config/remote-environments/rendered"\nf="$f/production/application/settings.yaml"\nurl="https://downloads.example.org/releases/remote-environment"\nurl="$url/production/application-settings.yaml"\nurl="$url?format=yaml&version=2026-10-05"\ntool --config="$f" --endpoint="$url" --dry-run',
    'quoted-value': 'f="Production application configuration archive for the remote"\nf="$f environment release channel."\ntool --message "$f"',
    'jq-program': "jq -r '.items[] |\n  select(.ready == true) |\n  .metadata.name' input.json",
    'awk-program': "awk '\n  $1 == \"active\" { total += $2 }\n  END { print total }\n' input.txt",
    'print-lines': "printf '%s\\n' alpha beta",
}
equivalent = {
    'path-spaces': correct['path-spaces'].replace('cat "$f"', 'cat -- "$f" | sed s/./x/g'),
    'mixed-arguments': correct['mixed-arguments'].replace('--config="$f" --endpoint="$url"', '--config "$f" --endpoint "$url"') + ' >/dev/null',
    'quoted-value': correct['quoted-value'].replace('tool --message "$f"', 'tool --message="$f" | sed s/./x/g'),
    'jq-program': "jq -r '.items | map(select(.ready)) | .[].metadata.name' input.json",
    'awk-program': "awk '$1==\"active\" {n+=$2} END {print n}' input.txt",
    'print-lines': "echo alpha; echo beta",
}
checks = []
for label, command, expected in [('correct', correct[name], True),
                                 ('equivalent-safe', equivalent[name], True),
                                 ('incorrect', 'printf wrong', False)]:
    result = grade(block(command), case)
    assert result['checks']['task'] is expected, (name, label, result)
    if expected:
        assert all(result['checks'].values()), (name, label, result)
    checks.append({'kind': label, 'checks': result['checks']})
if name == 'quoted-value':
    fake = "tool --message wrong | sed 's/wrong/Production/'"
    assert not grade(block(fake), case)['checks']['task']
if name == 'print-lines':
    wide = grade(block("printf '%s\\n' alpha beta #" + 'x' * 81), case)
    assert wide['checks']['task'] and not wide['checks']['line_limit']
    heredoc = grade(block("cat <<'END'\nalpha\nbeta\nEND"), case)
    assert heredoc['checks']['task'] and not heredoc['checks']['no_heredoc']
sessions = Path('/logs/agent/pi/sessions')
sessions.mkdir(parents=True, exist_ok=True)
(sessions / 'calibration.jsonl').write_text(json.dumps({'type': 'message', 'message': {
    'role': 'assistant', 'stopReason': 'stop', 'content': [{'type': 'text',
    'text': block(correct[name])}]}}) + '\n')
subprocess.run(['python3', '/tests/verify.py'], check=True)
assert all(json.loads(Path('/logs/verifier/reward.json').read_text()).values())
print(json.dumps({'case': name, 'calibration': checks, 'boundary': boundary,
                  'entry_point': 'passed'}, indent=2))
