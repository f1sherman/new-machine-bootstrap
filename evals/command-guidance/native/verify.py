"""Execute copy-paste answers without verifier authority, in the networkless verifier."""
import ctypes
import json
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import tempfile
import threading


UID = 1001


def restrict_child():
    os.setgroups([])
    os.setgid(UID)
    os.setuid(UID)
    # PR_SET_NO_NEW_PRIVS, including for setuid binaries in the image.
    assert ctypes.CDLL(None).prctl(38, 1, 0, 0, 0) == 0
    resource.setrlimit(resource.RLIMIT_CPU, (2, 2))
    resource.setrlimit(resource.RLIMIT_FSIZE, (1024 * 1024, 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_NPROC, (32, 32))
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024 * 1024, 256 * 1024 * 1024))
    os.umask(0o077)


def protect_verifier():
    assert os.getuid() == 0
    for name in ('/tests', '/logs', '/workspace'):
        path = Path(name)
        assert path.is_dir() and not path.is_symlink()
        os.chown(path, 0, 0)
        path.chmod(0o700)
    # No credential is installed in this fresh verifier image.
    assert not Path('/home/worker/.pi/agent/auth.json').exists()


def execute(command, case, shell):
    with tempfile.TemporaryDirectory(prefix='commands-') as directory:
        scratch = Path(directory)
        if case.get('program') in ('jq', 'awk'):
            (scratch / ('input.json' if case['program'] == 'jq' else 'input.txt')).write_text(case['input'])
        os.chown(scratch, UID, UID)
        scratch.chmod(0o700)
        read_fd, write_fd = os.pipe()
        records = bytearray()

        def collect():
            with os.fdopen(read_fd, 'rb') as stream:
                while chunk := stream.read(4096):
                    if len(records) < 65536:
                        records.extend(chunk[:65536 - len(records)])

        reader = threading.Thread(target=collect, daemon=True)
        reader.start()
        env = {'HOME': '/home/eval', 'PATH': '/usr/bin:/bin',
               'TMPDIR': directory, 'TMPPREFIX': directory + '/zsh', 'LC_ALL': 'C.UTF-8'}
        if 'calls' in case:
            env['PATH'] = '/opt/command-stubs:' + env['PATH']
        env['COMMAND_CAPTURE_FD'] = str(write_fd)
        # Output files are root-owned, unlinked, and never in candidate scratch.
        with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
            process = subprocess.Popen(['/bin/' + shell, '-f', '-eu', '-c', command],
                cwd=scratch, env=env, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                pass_fds=(write_fd,), preexec_fn=restrict_child, start_new_session=True)
            os.close(write_fd)
            timed_out = False
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                timed_out = True
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            reader.join(timeout=2)
            assert not reader.is_alive(), 'Capture pipe did not close'
            stdout.seek(0)
            stderr.seek(0)
            return {'status': process.returncode, 'timeout': timed_out,
                    'stdout': stdout.read().decode(errors='replace'),
                    'stderr': stderr.read().decode(errors='replace'),
                    'calls': [json.loads(line) for line in records.decode().splitlines()]}


def normalize(call, case):
    args = list(call['args'])
    if call['command'] == 'cat' and args[:1] == ['--']:
        args.pop(0)
    for canonical, aliases in case.get('options', {}).items():
        normalized = []
        for arg in args:
            option = next((name for name in [canonical, *aliases] if arg.startswith(name + '=')), None)
            if option:
                normalized.extend([canonical, arg[len(option) + 1:]])
            else:
                normalized.append(canonical if arg in aliases else arg)
        args = normalized
    return {'command': call['command'], 'args': args}


def grade(response, case):
    blocks = re.findall(r'```(?:bash|sh|shell|zsh)?[^\S\n]*\n(.*?)```', response, re.S)
    checks = {'answer_format': len(blocks) == 1, 'task': False,
              'line_limit': False, 'no_heredoc': False}
    details = {'checks': checks, 'shells': {}}
    if len(blocks) != 1:
        return details
    command = blocks[0]
    checks['answer_format'] = bool(command.strip())
    checks['line_limit'] = all(len(line) <= 80 for line in command.splitlines())
    # Conservative syntax screen; manual review distinguishes literal << data.
    checks['no_heredoc'] = '<<' not in command
    successful = []
    for shell in ('bash', 'zsh'):
        observed = execute(command, case, shell)
        details['shells'][shell] = observed
        valid = observed['status'] == 0 and not observed['timeout'] and not observed['stderr']
        if 'calls' in case:
            valid = valid and ([normalize(x, case) for x in observed['calls']]
                              == [normalize(x, case) for x in case['calls']])
        else:
            valid = valid and observed['stdout'] == case['stdout']
        successful.append(bool(valid))
    checks['task'] = all(successful)
    return details


def terminal_response():
    sessions = list(Path('/logs/agent/pi/sessions').glob('*.jsonl'))
    assert len(sessions) == 1, 'Expected one native session'
    messages = [entry['message'] for line in sessions[0].read_text().splitlines()
                if (entry := json.loads(line)).get('type') == 'message']
    assistants = [m for m in messages if m.get('role') == 'assistant']
    assert assistants and assistants[-1].get('stopReason') == 'stop', 'No terminal response'
    content = assistants[-1]['content']
    assert not any(p.get('type') == 'toolCall' for p in content), 'Unfinished tool call'
    return ''.join(p['text'] for p in content if p.get('type') == 'text')


if __name__ == '__main__':
    protect_verifier()
    result = grade(terminal_response(), json.loads(Path('/tests/case.json').read_text()))
    Path('/logs/verifier/assessment.json').write_text(json.dumps(result, indent=2) + '\n')
    Path('/logs/verifier/reward.json').write_text(json.dumps(
        {name: int(value) for name, value in result['checks'].items()}) + '\n')
