import asyncio
import base64
import json
import math
import os
from pathlib import Path
import tempfile
import time

from harbor.agents.installed.pi import Pi


AUTH_PATH = "/root/.pi/agent/auth.json"


async def access_credential():
    env = {name: os.environ[name] for name in ("PATH", "HOME") if name in os.environ}
    env.update(PI_CODING_AGENT_DIR=os.environ["PI_EVAL_HOST_AGENT_DIR"], PI_TELEMETRY="0")
    process = await asyncio.create_subprocess_exec(
        os.environ["PI_EVAL_HOST_PI"], "auth", "print-bearer-token",
        "--provider", "openai-codex", "--min-expiry", "5m",
        env=env, stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        stdout, _ = await asyncio.wait_for(process.communicate(), timeout=30)
    finally:
        if process.returncode is None:
            process.kill()
            await process.wait()
    if process.returncode != 0:
        raise RuntimeError("Pi login credential export failed; run pi auth check on the host")
    try:
        bearer = stdout.decode().strip()
        payload = bearer.split(".")[1]
        expires = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))["exp"]
        if (type(expires) not in (int, float) or not math.isfinite(expires)
                or expires < time.time() + 300):
            raise ValueError
    except (ValueError, KeyError, IndexError, TypeError, OverflowError, UnicodeError):
        raise RuntimeError("Pi login credential is malformed or expires too soon") from None
    return {"openai-codex": {"type": "oauth", "access": bearer,
                             "refresh": "", "expires": expires * 1000}}


class PiLogin(Pi):
    async def run(self, instruction, environment, context):
        if (not self.model_name.startswith("openai-codex/")
                or self.model_connection.configured_base_url
                or self.mcp_servers or self.options.config
                or self.options.model_api
                or self._get_env("PI_CODING_AGENT_DIR")):
            raise ValueError("Pi login requires the permission fixture's standard configuration")
        result = await environment.exec(command=(
            "mkdir -p /root/.pi/agent && chmod 700 /root/.pi/agent && "
            f"test ! -e {AUTH_PATH} && test ! -L {AUTH_PATH}"
        ))
        if result.return_code != 0:
            raise RuntimeError("Container credential path is not empty or accessible")
        credential = await access_credential()
        try:
            with tempfile.NamedTemporaryFile(
                    mode="w", prefix="pi-access-", dir=os.environ["TMPDIR"]) as source:
                json.dump(credential, source)
                source.flush()
                await environment.upload_file(Path(source.name), AUTH_PATH)
            result = await environment.exec(command=f"chmod 600 {AUTH_PATH}")
            if result.return_code != 0:
                raise RuntimeError("Cannot protect the container credential")
            if credential["openai-codex"]["expires"] / 1000 < time.time() + 270:
                raise RuntimeError("Pi login credential expires before the bounded step can finish")
            await super().run(instruction, environment, context)
        finally:
            result = await environment.exec(command=f"rm -f {AUTH_PATH}", timeout_sec=10)
            if result.return_code != 0:
                raise RuntimeError("Container credential cleanup failed")
