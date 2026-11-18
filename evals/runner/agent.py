"""Preinstalled native Pi; Harbor owns execution, logs, and lifecycle."""
import ipaddress
import json
import os
from pathlib import Path

from harbor.agents.installed.pi import Pi
from evals.harbor.pi_login import access_credential
from evals.runner.run import guidance_target, TLS_TIMEOUT_MARKER


class SandboxedPi(Pi):
    @staticmethod
    def _build_max_turns_extension(max_turns):
        # Harbor 0.26.0 aborts even a final answer at turn_end. Abort an excess
        # turn before its request instead; keep the native lifecycle and prompt.
        return f"""export default function (pi: any) {{
  const maxTurns = {max_turns};
  let startedTurns = 0;

  pi.on("before_agent_start", (event: any) => ({{
    systemPrompt: `${{event.systemPrompt}}\\n\\nYou have a hard budget of ${{maxTurns}} model turns. Complete the task and provide your final answer within that budget.`,
  }}));

  pi.on("turn_start", (_event: any, ctx: any) => {{
    if (startedTurns >= maxTurns) {{
      ctx.abort();
    }}
    startedTurns += 1;
  }});
}}
"""

    async def install(self, environment):
        raise RuntimeError("Build Pi into the image and use skip_install=true")

    async def configure(self, environment):
        if (not self.model_name.startswith(("openai/", "openai-codex/"))
                or self.model_connection.user_supplied_base_url is not None
                or self.mcp_servers or self.options.config or self.options.model_api):
            raise ValueError("Only the standard OpenAI inference providers are supported")
        address = os.environ.get('EVAL_INFERENCE_ADDRESS')
        if address:
            address = str(ipaddress.IPv4Address(address))
            host = 'chatgpt.com' if self.model_name.startswith('openai-codex/') else 'api.openai.com'
            result = await self.exec_as_root(environment,
                command=f"printf '\\n{address} {host}\\n' >> /etc/hosts", cwd='/')
            if result.return_code:
                raise RuntimeError('Cannot install frozen inference hostname')
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
if r.returncode == 28 and r.stdout in ('', '000'):
    raise AssertionError(os.environ['TLS_TIMEOUT_MARKER'])
assert r.returncode == 0 and r.stdout.isdigit() and int(r.stdout) > 0, r.stderr
print(json.dumps({'uid': os.getuid(), 'blocked': ['example.com', 'direct-ip', 'metadata', 'docker-host'],
                  'inference_tls': True, 'capabilities': 0, 'no_new_privileges': True}))
PY""", env={"INFERENCE_HOST": "chatgpt.com" if self.model_name.startswith("openai-codex/") else "api.openai.com",
           "TLS_TIMEOUT_MARKER": TLS_TIMEOUT_MARKER})
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
        target = guidance_target(os.environ.get("EVAL_GUIDANCE_TARGET", "AGENTS.md"))
        # Harbor uses a separate configuration directory for its turn extension.
        # Global context and skills remain in the normal HOME discovery paths.
        await self._upload_config_text(environment, content=guidance,
            remote_path="/home/worker/.pi/agent/" + target, filename=Path(target).name)
        if target != 'AGENTS.md' and guidance:
            # Use the installed parser before credentials or paid inference.
            await self.exec_as_agent(environment, command="""node --input-type=module - <<'JS'
import { loadSkills } from '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/dist/core/skills.js';
const file = process.env.EVAL_SKILL_FILE;
const { skills } = loadSkills({cwd: process.cwd(), agentDir: '/home/worker/.pi/agent', includeDefaults: true, skillPaths: []});
if (!skills.some(skill => skill.filePath === file)) {
  throw new Error('Expected skill is not discoverable');
}
JS""", env={'EVAL_SKILL_FILE': '/home/worker/.pi/agent/' + target})

    async def run(self, instruction, environment, context):
        auth_path = "/home/worker/.pi/agent/auth.json"
        oauth = self.model_name.startswith("openai-codex/")
        if oauth:
            # Cover the 900-second trial cap plus Pi's five-minute refresh window.
            credential = await access_credential(minimum_seconds=1200)
            await self._upload_config_text(environment, content=json.dumps(credential),
                remote_path=auth_path, filename="auth.json")
        try:
            await super().run(instruction, environment, context)
        finally:
            if oauth:
                result = await self.exec_as_root(environment, command=f"rm -f {auth_path}", cwd="/")
                if result.return_code:
                    raise RuntimeError("Container access credential cleanup failed")
