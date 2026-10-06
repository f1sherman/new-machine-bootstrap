"""One isolated command-generation response through Harbor's agent lifecycle."""

import shlex

from harbor.agents.capabilities import AgentCapabilities
from harbor.agents.installed.pi import Pi, PiOptions
from harbor.models.agent.context import AgentContext


class PromptOptions(PiOptions):
    system_prompt: str


class PromptOnlyPi(Pi):
    capabilities = AgentCapabilities()
    options_model = PromptOptions

    @staticmethod
    def name() -> str:
        return "pi-prompt-only"

    def get_version_command(self) -> str:
        return "pi --version"

    async def install(self, environment) -> None:
        # The pinned Docker layer is shared; each trial only verifies its CLI.
        await self.exec_as_agent(environment, command=f'test "$(pi --version)" = {shlex.quote(self.options.version)}')

    async def run(self, instruction, environment, context: AgentContext) -> None:
        if (self.skills_dir or self.mcp_servers or self.load_trajectory
                or self.options.prompt_template_path or self.options.max_turns
                or self.options.config or self.options.model_api):
            raise ValueError("Prompt-only evals do not accept extra context or prompt features")
        if not self.options.version or self.options.thinking != "medium":
            raise ValueError("Command evals require an exact Pi version and medium thinking")
        provider, model = self.model_name.split("/", 1)
        access = self.model_connection
        if provider not in ("openai", "anthropic") or access.configured_base_url:
            raise ValueError("Use a standard openai/model or anthropic/model connection")
        argv = ["pi", "--print", "--mode", "json", "--no-session", "--no-tools",
                "--no-extensions", "--no-skills", "--no-context-files",
                "--no-prompt-templates", "--no-themes", "--no-approve", "--offline",
                "--provider", provider, "--model", model, "--thinking", "medium",
                "--system-prompt", self.options.system_prompt, instruction]
        stdout = shlex.quote(str(self.environment_logs_dir / "pi.txt"))
        stderr = shlex.quote(str(self.environment_logs_dir / "pi.stderr"))
        await self.exec_as_agent(
            environment,
            command=f"{shlex.join(argv)} > {stdout} 2> {stderr} </dev/null",
            env=dict(access.env),
        )
