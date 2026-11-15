"""No-inference calibration, run only in a fresh networkless Docker container."""
import json
from pathlib import Path
import subprocess

from verify import execute, grade, protect_verifier


def block(command):
    return '```bash\n' + command + '\n```'


protect_verifier()
Path('/opt/cases').chmod(0o700)
cases = {path.parent.parent.name: json.loads(path.read_text())
         for path in Path('/opt/cases').glob('*/tests/case.json')}
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
for name, case in cases.items():
    for label, command, expected in [('correct', correct[name], True),
                                     ('equivalent-safe', equivalent[name], True),
                                     ('incorrect', 'printf wrong', False)]:
        result = grade(block(command), case)
        assert result['checks']['task'] is expected, (name, label, result)
        if expected:
            assert all(result['checks'].values()), (name, label, result)
        checks.append({'case': name, 'kind': label, 'checks': result['checks']})
fake = "tool --message wrong | sed 's/wrong/Production/'"
assert not grade(block(fake), cases['quoted-value'])['checks']['task']
wide = grade(block("printf '%s\\n' alpha beta #" + 'x' * 81), cases['print-lines'])
assert wide['checks']['task'] and not wide['checks']['line_limit']
heredoc = grade(block("cat <<'END'\nalpha\nbeta\nEND"), cases['print-lines'])
assert heredoc['checks']['task'] and not heredoc['checks']['no_heredoc']
probe = '''python3 -c 'import os, socket
assert os.getuid() == 1001
assert int(next(x.split()[1] for x in open("/proc/self/status") if x.startswith("CapEff:")), 16) == 0
assert next(x.split()[1] for x in open("/proc/self/status") if x.startswith("NoNewPrivs:")) == "1"
for p in ["/tests/verify.py", "/logs/verifier/sentinel", "/workspace/sentinel", "/proc/1/root/tests/verify.py"]:
 try: open(p).read()
 except PermissionError: pass
 else: raise AssertionError("Read protected file: " + p)
for p in ["/tests/injected", "/logs/verifier/reward.json", "/workspace/injected"]:
 try: open(p, "w").write("forged")
 except PermissionError: pass
 else: raise AssertionError("Wrote protected file: " + p)
try: os.setuid(0)
except PermissionError: pass
else: raise AssertionError("Regained root")
s = socket.socket(); s.settimeout(1)
try: s.connect(("1.1.1.1", 443))
except OSError: pass
else: raise AssertionError("Network available")
print("boundary-ok")' '''
Path('/logs/verifier/sentinel').write_text('protected')
Path('/workspace/sentinel').write_text('protected')
for shell in ('bash', 'zsh'):
    result = execute(probe, {'program': 'shell'}, shell)
    assert result['stdout'] == 'boundary-ok\n' and result['status'] == 0, result
sessions = Path('/logs/agent/pi/sessions')
sessions.mkdir(parents=True, exist_ok=True)
(sessions / 'calibration.jsonl').write_text(json.dumps({'type': 'message', 'message': {
    'role': 'assistant', 'stopReason': 'stop', 'content': [{'type': 'text',
    'text': block(correct['print-lines'])}]}}) + '\n')
Path('/tests/case.json').write_text(json.dumps(cases['print-lines']))
subprocess.run(['python3', '/tests/verify.py'], check=True)
assert all(json.loads(Path('/logs/verifier/reward.json').read_text()).values())
print(json.dumps({'calibration': checks, 'boundary': 'UID1001; caps0; NNP; protected reads/writes denied; network denied',
                  'entry_point': 'passed', 'additional': ['stdout-independent arguments', 'false arguments rejected', 'line limit separate', 'heredoc separate']}, indent=2))
