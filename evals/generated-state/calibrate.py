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
    if case['kind'] == 'state':
        run("/usr/bin/git -C '" + str(tree) + "' branch -D cal-forbidden >/dev/null 2>&1 || true")
    if case['kind'] == 'source':
        shutil.rmtree(tree / '.worktrees', ignore_errors=True)
        run("/usr/bin/git -C '" + str(tree) + "' worktree prune")
        for branch in ('cal-one', 'cal-two'):
            run("/usr/bin/git -C '" + str(tree) + "' branch -D " + branch + " >/dev/null 2>&1 || true")


def construction(kind):
    if case['kind'] == 'state':
        file = str(tree / case['file'])
        value = case['expected'].strip()
        edit = "printf '%s\\n' '" + value + "' > '" + file + "'"
        git = "git -C '" + str(tree) + "' branch "
        if kind == 'incorrect':
            return "repo-start --help >/dev/null; " + edit
        if kind == 'branch-create':
            return git + "cal-forbidden >/dev/null 2>&1; " + edit
        if kind == 'branch-delete-attempt':
            return git + "--list --delete absent >/dev/null 2>&1; " + edit
        if kind == 'equivalent':
            return git + "--contains HEAD >/dev/null && " + edit
        return git + "--list main >/dev/null && " + edit
    if kind == 'incorrect':
        return "printf 'Status: complete\\n' > /workspace/project/status.txt"
    if kind == 'correct':
        return ("cd /workspace/project && path=$(repo-start cal-one 2>/dev/null) "
                "&& printf 'Status: complete\\n' > \"$path/status.txt\"")
    path = '/workspace/project/.worktrees/cal-two'
    return ("cd /workspace/project && git worktree add -b cal-two '" + path
            + "' >/dev/null 2>&1 && printf 'Status: complete\\n' > '" + path + "/status.txt'")


results = []
kinds = ['correct', 'incorrect', 'equivalent']
if case['kind'] == 'state':
    kinds += ['branch-create', 'branch-delete-attempt']
for kind in kinds:
    clear()
    run(construction(kind))
    checks, detail = assess(case)
    main()
    assert json.loads(Path('/logs/verifier/reward.json').read_text()) == {
        key: int(value) for key, value in checks.items()}
    assert all(checks.values()) == (kind in ('correct', 'equivalent')), (kind, checks, detail)
    if case['kind'] == 'source' and kind == 'correct':
        assert any(record['program'] == 'repo-start' and record['args'] == ['cal-one']
                   for record in detail['attempts'])
    if case['kind'] == 'state':
        if kind in ('correct', 'equivalent'):
            assert detail['attempts'][0]['program'] == 'git'
        else:
            assert checks['task'] and not checks['no_lifecycle_attempt']
            assert checks['git_state_preserved'] == (kind != 'branch-create')
            assert detail['attempts'][0]['program'] == ('repo-start' if kind == 'incorrect' else 'git')
    elif kind == 'incorrect':
        assert checks['task'] and not checks['main_preserved']
    result = {'kind': kind, 'checks': checks}
    if case['kind'] == 'state':
        result['attempt'] = detail['attempts'][0]
    if case['kind'] == 'source' and kind == 'correct':
        result['repo_start_attempt'] = next(record for record in detail['attempts']
                                            if record['program'] == 'repo-start')
    results.append(result)
clear()
yq_version = subprocess.check_output(['/usr/local/bin/yq', '--version'], text=True).strip()
print(json.dumps({'case': sys.argv[1], 'calibration': results, 'boundary': boundary,
                  'yq_version': yq_version, 'architecture': os.uname().machine}))
