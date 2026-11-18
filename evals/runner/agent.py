"""Preinstalled native Pi; Harbor owns execution, logs, and lifecycle."""
import ipaddress
import json
import os
from pathlib import Path

from harbor.agents.installed.pi import Pi
from evals.harbor.pi_login import access_credential
from evals.runner.run import guidance_target, TLS_TIMEOUT_MARKER


class SandboxedPi(Pi):
    def _build_max_turns_extension(self, max_turns):
        # Keep normal native abort handling and the completed final answer.
        # Inspect skills during startup, not a second resource-loader pass.
        return f"""export default function (pi: any) {{
  const maxTurns = {max_turns};
  const expected = {json.dumps(self._guidance_guard)};
  let startedTurns = 0;

  pi.on("before_agent_start", (event: any, ctx: any) => {{
    if (expected) {{
      const skills = event.systemPromptOptions?.skills;
      const named = Array.isArray(skills) ? skills.filter((skill: any) => skill.name === expected.name) : null;
      if (!named || (expected.present
          ? !named.some((skill: any) => skill.filePath === expected.file && !skill.disableModelInvocation)
              || !event.systemPrompt.includes(`<location>${{expected.file}}</location>`)
          : named.length > 0)) {{
        console.error("EVAL_SKILL_DISCOVERY_REFUSED");
        ctx.abort();
        return;
      }}
    }}
    return {{
      systemPrompt: `${{event.systemPrompt}}\\n\\nYou have a hard budget of ${{maxTurns}} model turns. Complete the task and provide your final answer within that budget.`,
    }};
  }});

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
        self._guidance_guard = None
        if target != 'AGENTS.md':
            header = os.environ.get('EVAL_GUIDANCE_SKILL_HEADER')
            if not header:
                raise ValueError('Skill conditions require a frozen skill header')
            # Use Pi's YAML rules without loading resources or running preloads.
            parsed = await self.exec_as_agent(environment, command="""node --input-type=module - <<'JS'
import { parseFrontmatter } from '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/dist/utils/frontmatter.js';
try {
  const { frontmatter } = parseFrontmatter(process.env.EVAL_SKILL_HEADER);
  const name = typeof frontmatter.name === 'string' && frontmatter.name
    ? frontmatter.name : process.env.EVAL_SKILL_FALLBACK;
  process.stdout.write(JSON.stringify(name));
} catch {
  console.error('EVAL_SKILL_HEADER_INVALID');
  process.exitCode = 2;
}
JS""", env={'EVAL_SKILL_HEADER': header, 'EVAL_SKILL_FALLBACK': Path(target).parent.name,
            'NODE_OPTIONS': '', 'NODE_DISABLE_COMPILE_CACHE': '1'})
            if parsed.return_code:
                if parsed.return_code == 2 and parsed.stderr.strip() == 'EVAL_SKILL_HEADER_INVALID':
                    raise ValueError('Frozen skill header is invalid')
                raise RuntimeError('Native skill metadata parser failed')
            name = json.loads(parsed.stdout)
            if not isinstance(name, str) or not name:
                raise ValueError('Native skill name is invalid')
            # Inspect native startup metadata, after its one resource load. Do not
            # initialize extensions in a separate live-workspace preflight.
            self._guidance_guard = {'file': '/home/worker/.pi/agent/' + target,
                                    'name': name, 'present': bool(guidance)}

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
