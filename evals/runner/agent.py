"""Preinstalled native Pi; Harbor owns execution, logs, and lifecycle."""
import json
import os
from pathlib import Path

from harbor.agents.installed.pi import Pi
from evals.harbor.pi_login import access_credential


class SandboxedPi(Pi):
    async def install(self, environment):
        raise RuntimeError("Build Pi into the image and use skip_install=true")

    async def configure(self, environment):
        if (not self.model_name.startswith(("openai/", "openai-codex/"))
                or self.model_connection.user_supplied_base_url is not None
                or self.mcp_servers or self.options.config or self.options.model_api):
            raise ValueError("Only the standard OpenAI inference providers are supported")
        # This is executed through Harbor in the agent's network namespace.
        probe = await self.exec_as_agent(environment, command="""python3 - <<'PY'
import json, os, subprocess
assert os.getuid() == 1001
assert not os.path.exists('/var/run/docker.sock')
assert int(next(x.split()[1] for x in open('/proc/self/status') if x.startswith('CapEff:')), 16) == 0
assert next(x.split()[1] for x in open('/proc/self/status') if x.startswith('NoNewPrivs:')) == '1'
# Harbor's transparent proxy can accept TCP before it rejects TLS/HTTP.
# Check completed application connections, not just the TCP handshake.
for url in ('https://example.com', 'https://1.1.1.1',
            'http://169.254.169.254', 'http://host.docker.internal'):
    blocked = subprocess.run(['curl', '--noproxy', '*', '--silent', '--show-error',
        '--max-time', '3', '--output', '/dev/null', url], capture_output=True)
    assert blocked.returncode != 0, 'Unexpected network access: ' + url
# A real TLS response proves the inference route; no credential is used.
r = subprocess.run(['curl', '--silent', '--show-error', '--max-time', '15',
                    '--output', '/dev/null', '--write-out', '%{http_code}',
                    'https://' + os.environ['INFERENCE_HOST'] + '/'], capture_output=True, text=True)
assert r.returncode == 0 and r.stdout.isdigit() and int(r.stdout) > 0, r.stderr
print(json.dumps({'uid': os.getuid(), 'blocked': ['example.com', 'direct-ip', 'metadata', 'docker-host'],
                  'inference_tls': True, 'capabilities': 0, 'no_new_privileges': True}))
PY""", env={"INFERENCE_HOST": "chatgpt.com" if self.model_name.startswith("openai-codex/") else "api.openai.com"})
        if probe.return_code != 0:
            raise RuntimeError("Sandbox preflight failed: " + (probe.stderr or probe.stdout or ""))
        (self.logs_dir / "boundary.json").write_text(probe.stdout)
        version = await self.exec_as_agent(environment, command="pi --version")
        if version.return_code or version.stdout.strip() != self._version:
            raise RuntimeError("Installed Pi differs from the frozen version")
        prepared = await self.exec_as_agent(environment,
            command="mkdir -p /home/worker/.pi/agent && chmod 700 /home/worker/.pi/agent")
        if prepared.return_code:
            raise RuntimeError("Cannot prepare isolated Pi configuration")
        guidance = Path(os.environ["EVAL_GUIDANCE_FILE"]).read_text()
        await self._upload_config_text(environment, content=guidance,
            remote_path="/home/worker/.pi/agent/AGENTS.md", filename="AGENTS.md")

    async def run(self, instruction, environment, context):
        auth_path = "/home/worker/.pi/agent/auth.json"
        oauth = self.model_name.startswith("openai-codex/")
        if oauth:
            credential = await access_credential()
            await self._upload_config_text(environment, content=json.dumps(credential),
                remote_path=auth_path, filename="auth.json")
        try:
            await super().run(instruction, environment, context)
        finally:
            if oauth:
                result = await self.exec_as_root(environment, command=f"rm -f {auth_path}", cwd="/")
                if result.return_code:
                    raise RuntimeError("Container access credential cleanup failed")
