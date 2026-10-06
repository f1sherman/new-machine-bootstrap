"""Harbor verifier that retains the macOS command sandbox and Ruby grader."""

import asyncio
import json
import os
from pathlib import Path

from harbor.models.verifier.result import VerifierResult
from harbor.verifier.base import BaseVerifier

ROOT = Path(__file__).resolve().parents[2]


class MacOSCommandVerifier(BaseVerifier):
    async def verify(self) -> VerifierResult:
        request = json.loads((self.task.paths.tests_dir / "case.json").read_text())
        request["events"] = (self.trial_paths.agent_dir / "pi.txt").read_text()
        request_path = self.trial_paths.verifier_dir / "request.json"
        request_path.write_text(json.dumps(request))
        # Trusted grading code gets no model credentials; generated shell code is
        # further isolated by the grader's default-deny macOS sandbox and env -i.
        env = {key: os.environ[key] for key in ("PATH", "LANG", "TMPDIR") if key in os.environ}
        env["COMMAND_GUIDANCE_EVAL_SCRATCH"] = str(ROOT / "tmp/command-guidance")
        process = await asyncio.create_subprocess_exec(
            "ruby", str(self.task.paths.tests_dir / "grader.rb"), str(request_path),
            cwd=ROOT, env=env, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        try:
            out, err = await asyncio.wait_for(process.communicate(), timeout=20)
        finally:
            if process.returncode is None:
                process.kill()
                await process.wait()
        (self.trial_paths.verifier_dir / "grader.stderr").write_bytes(err)
        assessment = json.loads(out)
        (self.trial_paths.verifier_dir / "assessment.json").write_text(json.dumps(assessment, indent=2) + "\n")
        if process.returncode != 0 or assessment.get("infrastructure_error"):
            raise RuntimeError(assessment.get("infrastructure_error", "grader process failed"))
        grade = assessment["grade"]
        failures = grade["failures"]
        observed = sorted(grade.get("shells", {})) == ["bash", "zsh"]
        rewards = {
            "reward": int(grade["pass"]),
            "functional": int(observed and not any(not f.startswith("format:") for f in failures)),
            "format_policy": int("shells" in grade and not any(f.startswith("format:") for f in failures)),
        }
        self.trial_paths.reward_json_path.write_text(json.dumps(rewards) + "\n")
        return VerifierResult(rewards=rewards)
