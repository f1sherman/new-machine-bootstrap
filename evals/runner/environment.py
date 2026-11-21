"""Record the actual Docker image before Harbor hands the container to either role."""
import asyncio
import json
import os

from harbor.environments.docker.docker import DockerEnvironment

from evals.runner.run import is_image_id, save


class PinnedDocker(DockerEnvironment):
    async def _ensure_egress_control_sidecar_image_built(self):
        image = os.environ.get("NMB_EVAL_SIDECAR_IMAGE")
        if not is_image_id(image):
            raise ValueError("Missing immutable egress sidecar pin")
        if await self._inspect("image", image, "{{.Id}}") != image:
            raise ValueError("Pinned egress sidecar is not available locally")
        self._env_vars.egress_control_sidecar_image_name = image

    async def start(self, force_build: bool):
        mode = self.network_policy.network_mode.value
        role = {"allowlist": "candidate", "no-network": "verifier"}[mode]
        expected = json.loads(os.environ["NMB_EVAL_IMAGE_PINS"])[role]
        if force_build or not is_image_id(expected) or self.task_env_config.docker_image != expected:
            raise ValueError(f"{role} must start with its pinned image ID, without rebuild")
        if await self._inspect("image", expected, "{{.Id}}") != expected:
            raise ValueError(f"{role} pinned image is not available locally")

        await super().start(force_build=False)
        actual, container, network = await self._inspect_service("main")
        sidecar, sidecar_container, _ = await self._inspect_service(self._EGRESS_CONTROL_SERVICE_NAME)
        # The trial root, unlike the agent logs and artifacts, is not mounted.
        save(self.trial_paths.trial_dir / f"{role}-image.json",
             {"image": actual, "container": container, "network": network, "policy": mode,
              "sidecar_image": sidecar, "sidecar_container": sidecar_container})
        if actual != expected:
            raise ValueError(f"{role} image mismatch: expected {expected}, got {actual}")
        if sidecar != os.environ["NMB_EVAL_SIDECAR_IMAGE"] or network != f"container:{sidecar_container}":
            raise ValueError(f"{role} egress sidecar image or namespace mismatch")

    async def _inspect_service(self, service):
        ps = await self._run_docker_compose_command(["ps", "-q", service])
        containers = (ps.stdout or "").split()
        if len(containers) != 1:
            raise ValueError(f"Expected exactly one live container for {service}")
        return (await self._inspect(
            "container", containers[0], "{{.Image}} {{.Id}} {{.HostConfig.NetworkMode}}"
        )).split()

    async def _inspect(self, kind, target, format_string):
        command = self.runtime().engine_cmd(kind, "inspect", "--format", format_string, target)
        process = await asyncio.create_subprocess_exec(*command, stdout=asyncio.subprocess.PIPE,
                                                       stderr=asyncio.subprocess.DEVNULL)
        try:
            output, _ = await process.communicate()
        finally:
            if process.returncode is None:
                process.kill()
                await process.wait()
        if process.returncode:
            raise ValueError(f"Docker could not inspect {kind} {target}")
        return output.decode().strip()
