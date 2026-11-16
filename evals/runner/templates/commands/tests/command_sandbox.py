"""Run generated shell as UID1001, never with verifier authority."""
import ctypes
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
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
    assert not Path('/home/worker/.pi/agent/auth.json').exists()


def execute(command, shell, *, files=None, capture=False):
    if shell not in ('bash', 'zsh'):
        raise ValueError('Use bash or zsh')
    with tempfile.TemporaryDirectory(prefix='commands-') as directory:
        scratch = Path(directory)
        for name, text in (files or {}).items():
            if Path(name).name != name:
                raise ValueError('Scratch inputs must be plain filenames')
            (scratch / name).write_text(text)
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
        if capture:
            env['PATH'] = '/opt/command-stubs:' + env['PATH']
        env['COMMAND_CAPTURE_FD'] = str(write_fd)
        # Unlinked output files never enter candidate scratch. A trusted bootstrap
        # drops privileges before exec; preexec_fn is unsafe with a reader thread.
        with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
            try:
                process = subprocess.Popen([sys.executable, __file__, shell, command],
                    cwd=scratch, env=env, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                    pass_fds=(write_fd,), start_new_session=True)
            finally:
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


def calibrate_boundary():
    """Probe the same execution path used by study graders, inside the container."""
    protect_verifier()
    Path('/logs/verifier/sentinel').write_text('protected')
    Path('/workspace/sentinel').write_text('protected')
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
    for shell in ('bash', 'zsh'):
        result = execute(probe, shell)
        assert result['stdout'] == 'boundary-ok\n' and result['status'] == 0, result
        assert not result['stderr'] and not result['timeout'], result
        result = execute('sleep 10', shell)
        assert result['timeout'] and result['status'] != 0, result
    return 'UID1001; caps0; NNP; protected reads/writes denied; network denied; timeout enforced'


if __name__ == '__main__':
    shell, command = sys.argv[1:]
    if shell not in ('bash', 'zsh'):
        raise ValueError('Use bash or zsh')
    restrict_child()
    os.execv('/bin/' + shell, [shell, '-f', '-eu', '-c', command])
