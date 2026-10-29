import base64
import json
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import tempfile
import time
import unittest
from unittest.mock import AsyncMock, patch

from harbor.agents.installed.pi import Pi
from harbor.models.agent.context import AgentContext

from evals.harbor.pi_login import PiLogin

ROOT = Path(__file__).resolve().parents[2]


def token(expiry):
    payload = base64.urlsafe_b64encode(json.dumps({"exp": expiry}).encode()).decode().rstrip("=")
    return f"fixture.{payload}.fixture-secret"


class PiLoginTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        scratch = ROOT / "tmp/harbor-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.bearer = token(int(time.time()) + 3600)
        self.fake = self.directory / "pi"
        self.fake.write_text(f"#!{sys.executable}\nprint({self.bearer!r})\n")
        self.fake.chmod(0o700)
        self.env = patch.dict(os.environ, {
            "PI_EVAL_HOST_PI": str(self.fake),
            "PI_EVAL_HOST_AGENT_DIR": str(self.directory / "host-agent"),
            "TMPDIR": str(self.directory),
        })
        self.env.start()
        self.addCleanup(self.env.stop)

    def environment(self):
        environment = AsyncMock()
        environment.exec.return_value.return_code = 0
        return environment

    def agent(self):
        return PiLogin(logs_dir=self.directory / "logs",
                       environment_logs_dir=PurePosixPath("/logs/agent"),
                       model_name="openai-codex/fixture", version="1.4.0", max_turns=12)

    async def test_native_run_gets_access_only_private_credential_and_cleans_it(self):
        uploaded = []
        sources = []
        environment = self.environment()

        async def upload(source_path, target_path):
            source = Path(source_path)
            sources.append(source)
            self.assertEqual(stat.S_IMODE(source.stat().st_mode), 0o600)
            uploaded.append((target_path, json.loads(source.read_text())))

        environment.upload_file.side_effect = upload
        with patch.object(Pi, "run", new_callable=AsyncMock) as native:
            agent = self.agent()
            context = AgentContext()
            await agent.run("fixture instruction", environment, context)
            native.assert_awaited_once_with("fixture instruction", environment, context)
        self.assertEqual(uploaded, [("/root/.pi/agent/auth.json", {"openai-codex": {
            "type": "oauth", "access": self.bearer, "refresh": "",
            "expires": json.loads(base64.urlsafe_b64decode(self.bearer.split(".")[1] + "=="))["exp"] * 1000,
        }})])
        self.assertTrue(all(not source.exists() for source in sources))
        calls = str(environment.exec.await_args_list)
        self.assertIn("rm -f", calls)
        self.assertNotIn(self.bearer, calls)
        self.assertNotIn(self.bearer, str(agent.options.model_dump()))

    async def test_partial_upload_and_native_failure_both_remove_credentials(self):
        for fail_upload in (True, False):
            with self.subTest(fail_upload=fail_upload):
                environment = self.environment()
                if fail_upload:
                    environment.upload_file.side_effect = RuntimeError("partial upload")
                with patch.object(Pi, "run", new_callable=AsyncMock,
                                  side_effect=RuntimeError("native failed")):
                    with self.assertRaises(RuntimeError):
                        await self.agent().run("fixture", environment, AgentContext())
                self.assertIn("rm -f", str(environment.exec.await_args_list))
                self.assertFalse(list(self.directory.glob("pi-access-*")))

    async def test_expired_malformed_or_failed_auth_never_reaches_container(self):
        for value in (token(time.time() - 1), token(time.time() + 100),
                      token(True), token(float("inf")), "not-a-token"):
            with self.subTest(value=value):
                self.fake.write_text(f"#!{sys.executable}\nprint({value!r})\n")
                environment = self.environment()
                with self.assertRaisesRegex(RuntimeError, "credential"):
                    await self.agent().run("fixture", environment, AgentContext())
                environment.upload_file.assert_not_awaited()
        self.fake.write_text(f"#!{sys.executable}\nimport sys\nprint('secret-failure',file=sys.stderr)\nsys.exit(1)\n")
        with self.assertRaisesRegex(RuntimeError, "Pi login") as error:
            await self.agent().run("fixture", self.environment(), AgentContext())
        self.assertNotIn("secret-failure", str(error.exception))

    async def test_existing_container_credential_is_not_overwritten_or_deleted(self):
        environment = self.environment()
        environment.exec.return_value.return_code = 1
        with self.assertRaisesRegex(RuntimeError, "credential"):
            await self.agent().run("fixture", environment, AgentContext())
        environment.upload_file.assert_not_awaited()
        self.assertNotIn("rm -f", str(environment.exec.await_args_list))
