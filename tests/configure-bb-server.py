#!/usr/bin/env python3
"""Exercise saved bb server selection through the real Ansible action."""

import errno
import json
import os
from pathlib import Path
import pty
import select
import shlex
import signal
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
PERSONAL_URL = "https://bb.brianjohn.com"


class ConfigureBBServerTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / "state/bb-server.json"
        self.playbook = Path(self.directory.name) / "playbook.json"
        self.playbook.write_text(json.dumps([{
            "hosts": "localhost", "connection": "local", "gather_facts": False,
            "tasks": [{"configure_bb_server": {"path": str(self.config)}}]
        }]))
        self.environment = dict(os.environ, ANSIBLE_ACTION_PLUGINS=str(ROOT / "action_plugins"),
                                ANSIBLE_NOCOLOR="1", ANSIBLE_FORCE_COLOR="0")

    def command(self, check=False):
        command = ["ansible-playbook", "-i", "localhost,", str(self.playbook)]
        return command + (["--check"] if check else [])

    def terminal(self, answers):
        pid, terminal = pty.fork()
        if pid == 0:
            # Match bin/provision's output pipeline while keeping terminal stdin.
            command = shlex.join(self.command()) + " | tee /dev/null"
            os.execvpe("bash", ["bash", "-o", "pipefail", "-c", command], self.environment)
        output = b""
        remaining = list(answers)
        answered_prompts = 0
        deadline = time.monotonic() + 20
        try:
            while True:
                if time.monotonic() > deadline:
                    self.fail("Action hung: " + output.decode(errors="replace"))
                if not select.select([terminal], [], [], 0.1)[0]:
                    continue
                try:
                    data = os.read(terminal, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                output += data
                if output.count(b"Selection: ") > answered_prompts and remaining:
                    # Wait until Ansible has switched the terminal into input mode.
                    while termios.tcgetattr(terminal)[3] & termios.ICANON:
                        if time.monotonic() > deadline:
                            self.fail("Prompt did not enter input mode")
                        time.sleep(0.01)
                    time.sleep(0.1)
                    os.write(terminal, remaining.pop(0))
                    answered_prompts += 1
            _, status = os.waitpid(pid, 0)
            pid = None
            return os.waitstatus_to_exitcode(status), output.decode(errors="replace")
        finally:
            os.close(terminal)
            if pid is not None:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)

    def detached(self, check=False):
        return subprocess.run(self.command(check), stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, env=self.environment,
                              start_new_session=True, timeout=20)

    def test_personal_choice_is_saved_and_reused_without_terminal(self):
        status, output = self.terminal([b"1\n"])
        self.assertEqual(status, 0, output)
        self.assertIn("Personal machines", output)
        self.assertIn("Work machines", output)
        self.assertIn(PERSONAL_URL, output)
        self.assertIn("changed=1", output)
        self.assertEqual(json.loads(self.config.read_text()), {"server_url": PERSONAL_URL})
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
        before = self.config.stat().st_mtime_ns
        repeat = self.detached()
        self.assertEqual(repeat.returncode, 0, repeat.stdout + repeat.stderr)
        self.assertIn("changed=0", repeat.stdout)
        self.assertEqual(self.config.stat().st_mtime_ns, before)
        self.assertNotIn("Selection", repeat.stderr + repeat.stdout)

    def test_blank_work_choice_is_saved_and_not_prompted_again(self):
        status, output = self.terminal([b"\n"])
        self.assertEqual(status, 0, output)
        self.assertEqual(json.loads(self.config.read_text()), {"server_url": None})
        repeat = self.detached()
        self.assertEqual(repeat.returncode, 0, repeat.stdout + repeat.stderr)
        self.assertIn("changed=0", repeat.stdout)
        self.assertNotIn("Selection", repeat.stdout + repeat.stderr)

    def test_custom_url_is_saved(self):
        status, output = self.terminal([b"https://bb.example.test:443/bb\n"])
        self.assertEqual(status, 0, output)
        self.assertEqual(json.loads(self.config.read_text())["server_url"],
                         "https://bb.example.test:443/bb")

    def test_invalid_selection_reprompts_without_saving_it(self):
        status, output = self.terminal([b"not-a-url\n", b"1\n"])
        self.assertEqual(status, 0, output)
        self.assertEqual(output.count("Selection: "), 2)
        self.assertEqual(json.loads(self.config.read_text()), {"server_url": PERSONAL_URL})

    def test_first_run_without_terminal_does_not_save_blank(self):
        result = self.detached()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("interactive terminal", result.stdout + result.stderr)
        self.assertFalse(self.config.exists())

    def test_eof_does_not_save_blank(self):
        status, output = self.terminal([b"\x04"])
        self.assertNotEqual(status, 0, output)
        self.assertFalse(self.config.exists())

    def test_interrupt_does_not_save_blank(self):
        status, output = self.terminal([b"\x03"])
        self.assertNotEqual(status, 0, output)
        self.assertFalse(self.config.exists())

    def test_invalid_saved_state_is_not_overwritten(self):
        for document in [{}, [], {"server_url": 1}, {"server_url": ""},
                         {"server_url": "ftp://bb.example.test"},
                         {"server_url": "https://user:secret@bb.example.test"},
                         {"server_url": "https://bb.example.test?key=secret"},
                         {"server_url": "https://bb.example.test/#secret"},
                         {"server_url": "https://bb.example.test/path with spaces"}]:
            with self.subTest(document=document):
                self.config.parent.mkdir(exist_ok=True)
                self.config.write_text(json.dumps(document))
                before = self.config.read_bytes()
                result = self.detached()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid", result.stdout + result.stderr)
                self.assertEqual(self.config.read_bytes(), before)
                self.assertNotIn("secret", result.stdout + result.stderr)

    def test_corrupt_saved_json_is_not_overwritten(self):
        self.config.parent.mkdir()
        self.config.write_text("{broken")
        result = self.detached()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid", result.stdout + result.stderr)
        self.assertEqual(self.config.read_text(), "{broken")

    def test_check_mode_does_not_prompt_or_save(self):
        result = self.detached(check=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("changed=0", result.stdout)
        self.assertFalse(self.config.exists())
        self.assertNotIn("Selection", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
