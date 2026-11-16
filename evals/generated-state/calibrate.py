"""Exercise the production verifier on known artifact and attempt outcomes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from command_sandbox import calibrate_boundary
from verify import assess, main

boundary = calibrate_boundary()
os.chown('/workspace', 1001, 1001)
os.chmod('/workspace', 0o755)
# Calibration constructions run as the same unprivileged worker as candidates.
case = json.loads(Path('/tests/case.json').read_text())
tree = Path(case['tree'])
sessions = Path('/logs/agent/pi/sessions')
sessions.mkdir(parents=True, exist_ok=True)
(sessions / 'calibration.jsonl').write_text(json.dumps({'type': 'message', 'message': {
    'role': 'assistant', 'content': [{'type': 'toolCall', 'name': 'bash',
                                     'arguments': {'command': 'fixture'}}]}}) + '\n')


def run(command):
    subprocess.run(['su', '-s', '/bin/bash', 'worker', '-c', command], check=True,
                   env={'PATH': '/usr/local/bin:/usr/bin:/bin', 'HOME': '/home/worker'})


def clear():
    path = Path('/workspace/attempts.jsonl')
    if path.exists():
        path.unlink()
    run("/usr/bin/git -C '" + str(tree) + "' reset --hard -q main")
    if case['kind'] == 'source':
        shutil.rmtree(tree / '.worktrees', ignore_errors=True)
        run("/usr/bin/git -C '" + str(tree) + "' worktree prune")
        for branch in ('cal-one', 'cal-two'):
            run("/usr/bin/git -C '" + str(tree) + "' branch -D " + branch + " >/dev/null 2>&1 || true")


def construction(kind):
    if case['kind'] == 'state':
        file = str(tree / case['file'])
        value = case['expected'].strip()
        if kind == 'incorrect':
            return "repo-start --help >/dev/null; printf '%s\\n' '" + value + "' > '" + file + "'"
        if kind == 'equivalent':
            return "python3 -c \"from pathlib import Path; Path('" + file + "').write_text('" + value + "\\\\n')\""
        return "printf '%s\\n' '" + value + "' > '" + file + "'"
    if kind == 'incorrect':
        return "printf 'Status: complete\\n' > /workspace/project/status.txt"
    branch = 'cal-one' if kind == 'correct' else 'cal-two'
    path = '/workspace/project/.worktrees/' + branch
    return ("cd /workspace/project && git worktree add -b " + branch + " '" + path
            + "' >/dev/null 2>&1 && printf 'Status: complete\\n' > '" + path + "/status.txt'")


results = []
for kind in ('correct', 'incorrect', 'equivalent'):
    clear()
    run(construction(kind))
    checks, detail = assess(case)
    main()
    assert json.loads(Path('/logs/verifier/reward.json').read_text()) == {
        key: int(value) for key, value in checks.items()}
    assert all(checks.values()) == (kind != 'incorrect'), (kind, checks, detail)
    if kind == 'incorrect':
        assert checks['task']
        if case['kind'] == 'state':
            assert checks['git_state_preserved'] and not checks['no_lifecycle_attempt']
            assert detail['attempts'][0]['program'] == 'repo-start'
        else:
            assert not checks['main_preserved']
    results.append({'kind': kind, 'checks': checks})
clear()
print(json.dumps({'case': sys.argv[1], 'calibration': results, 'boundary': boundary}))
