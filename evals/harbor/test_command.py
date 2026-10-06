import asyncio
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path, PurePosixPath
import tempfile
from types import SimpleNamespace
import unittest

from harbor.environments.base import ExecResult
from harbor.models.agent.context import AgentContext
from harbor.models.task.task import Task
from harbor.models.trial.config import VerifierConfig
from harbor.models.trial.paths import TrialPaths
from harbor.verifier.factory import VerifierFactory
from evals.harbor.prompt_agent import PromptOnlyPi

ROOT = Path(__file__).resolve().parents[2]


class CommandHarborTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        scratch = ROOT / "tmp" / "harbor-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def task(self, response="```sh\ncat /tmp/rendered/service/config.yaml\n```", settled=True):
        task_dir = self.directory / "case"
        (task_dir / "tests").mkdir(parents=True)
        (task_dir / "environment").mkdir()
        (task_dir / "environment" / "Dockerfile").write_text("FROM scratch\n")
        (task_dir / "task.toml").write_text('schema_version = "1.3"\n')
        (task_dir / "instruction.md").write_text("fixture prompt")
        (task_dir / "tests" / "test.sh").write_text("#!/bin/sh\nexit 1\n")
        settings = {"provider": "openai", "model": "fixture", "thinking": "medium",
                    "system_prompt": "fixture system", "prompt": "fixture prompt"}
        payload = {"settings": settings, "test_case": {"calls": [
            {"command": "cat", "args": ["/tmp/rendered/service/config.yaml"]}]}}
        (task_dir / "tests" / "case.json").write_text(json.dumps(payload))
        (task_dir / "tests" / "grader.rb").write_bytes((ROOT / "evals/command-guidance/grader.rb").read_bytes())
        paths = TrialPaths(self.directory / "trial")
        paths.mkdir()
        message = {"role": "assistant", "stopReason": "stop", "provider": "openai",
                   "model": "fixture", "usage": {"input": 9, "output": 4},
                   "content": [{"type": "text", "text": response}]}
        events = [{"type": "message_end", "message": {"role": "system",
                   "sections": {"preamble": settings["system_prompt"]}}},
                  {"type": "message_end", "message": {"role": "user", "content": [
                   {"type": "text", "text": settings["prompt"]}]}},
                  {"type": "message_end", "message": message}]
        if settled:
            events.append({"type": "agent_settled"})
        (paths.agent_dir / "pi.txt").write_text("\n".join(map(json.dumps, events)))
        self.assertIsNotNone(importlib.util.find_spec("evals.harbor.command_verifier"),
                             "native Harbor command verifier is not implemented")
        config = VerifierConfig(import_path="evals.harbor.command_verifier:MacOSCommandVerifier")
        verifier = VerifierFactory.create_verifier_from_config(
            config, task=Task(task_dir), trial_paths=paths,
            environment=SimpleNamespace(capabilities=SimpleNamespace(mounted=True)))
        return verifier, paths

    async def test_native_verifier_returns_real_shell_rewards(self):
        verifier, paths = self.task()
        result = await verifier.verify()
        self.assertEqual(result.rewards, {"reward": 1, "functional": 1, "format_policy": 1})
        assessment = json.loads((paths.verifier_dir / "assessment.json").read_text())
        self.assertEqual(assessment["usage"], {"input": 9, "output": 4})
        self.assertEqual(assessment["grade"]["shells"]["bash"]["calls"],
                         [{"command": "cat", "args": ["/tmp/rendered/service/config.yaml"]}])

    async def test_command_verifier_executes_frozen_grader_without_mutating_task(self):
        verifier, paths = self.task()
        grader = self.directory / "case/tests/grader.rb"
        grader.write_text(grader.read_text().replace('failures = []',
                          'failures = ["format: frozen policy rejects this response"]'))
        before = sorted(str(file.relative_to(self.directory / "case"))
                        for file in (self.directory / "case").rglob("*") if file.is_file())
        result = await verifier.verify()
        self.assertEqual(result.rewards, {"reward": 0, "functional": 1, "format_policy": 0})
        assessment = json.loads((paths.verifier_dir / "assessment.json").read_text())
        self.assertIn("format: frozen policy rejects this response", assessment["grade"]["failures"])
        after = sorted(str(file.relative_to(self.directory / "case"))
                       for file in (self.directory / "case").rglob("*") if file.is_file())
        self.assertEqual(before, after, "Host grading must not create scratch artifacts in frozen inputs")

    async def test_native_verifier_retains_ungradable_outputs_as_model_failures(self):
        verifier, paths = self.task(response="No code fences.")
        result = await verifier.verify()
        self.assertEqual(result.rewards, {"reward": 0, "functional": 0, "format_policy": 0})
        assessment = json.loads((paths.verifier_dir / "assessment.json").read_text())
        self.assertEqual(assessment["response"], "No code fences.")
        self.assertEqual(assessment["usage"], {"input": 9, "output": 4})
        self.assertTrue(assessment["grade"]["ungradable"])

    async def test_native_verifier_keeps_format_score_when_execution_times_out(self):
        verifier, _ = self.task(response="```sh\nwhile :; do :; done\n```")
        result = await verifier.verify()
        self.assertEqual(result.rewards, {"reward": 0, "functional": 0, "format_policy": 1})

    async def test_native_verifier_rejects_incomplete_stream(self):
        verifier, _ = self.task(settled=False)
        with self.assertRaisesRegex(RuntimeError, "settled"):
            await verifier.verify()

    async def test_prompt_agent_preserves_isolated_cli_transport(self):
        self.assertIsNotNone(importlib.util.find_spec("evals.harbor.prompt_agent"),
                             "prompt-only Harbor adapter is not implemented")
        home = self.directory / "home"
        home.mkdir()
        bindir = self.directory / "bin"
        bindir.mkdir()
        capture = self.directory / "argv.json"
        fake = bindir / "pi"
        fake.write_text(f"#!{sys.executable}\nimport json,sys\nfrom pathlib import Path\n"
                        f"Path({str(capture)!r}).write_text(json.dumps(sys.argv[1:]))\n"
                        "print('native stdout')\nprint('native stderr',file=sys.stderr)\n")
        fake.chmod(0o755)
        logs = self.directory / "logs"
        logs.mkdir()
        env = {"HOME": str(home), "PATH": f"{bindir}:{os.environ['PATH']}"}

        class Environment:
            async def exec(inner, command, **kwargs):
                process = await asyncio.create_subprocess_exec(
                    "/bin/bash", "-c", command, cwd=self.directory,
                    env={**env, **(kwargs.get("env") or {})},
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
                out, err = await process.communicate()
                return ExecResult(stdout=out.decode(), stderr=err.decode(), return_code=process.returncode)

        system = "Use quoted \"$f\"; don't split arguments.\nSecond line."
        prompt = "Read the file called 'sample'.\nDo not execute anything."
        agent = await asyncio.to_thread(
            PromptOnlyPi, logs_dir=logs, environment_logs_dir=PurePosixPath(logs),
            model_name="openai/fixture", system_prompt=system,
            version="1.0.2", thinking="medium", extra_env={"OPENAI_API_KEY": "fixture-key"})
        await asyncio.to_thread(lambda: agent.model_connection)
        try:
            await agent.run(prompt, Environment(), AgentContext())
        except Exception as error:
            stderr_file = logs / "pi.stderr"
            self.fail(f"{error}\n{stderr_file.read_text() if stderr_file.exists() else 'no stderr artifact'}")
        args = json.loads(capture.read_text())
        for flag in ("--no-session", "--no-tools", "--no-extensions", "--no-skills",
                     "--no-context-files", "--no-prompt-templates", "--no-themes",
                     "--no-approve", "--offline"):
            self.assertIn(flag, args)
        self.assertEqual(args[args.index("--system-prompt") + 1], system)
        self.assertEqual(args[-1], prompt)
        self.assertEqual(args[args.index("--thinking") + 1], "medium")
        self.assertEqual((logs / "pi.txt").read_text(), "native stdout\n")
        self.assertEqual((logs / "pi.stderr").read_text(), "native stderr\n")

    def driver(self, *args, env=None):
        if env is None:
            env = {key: value for key, value in os.environ.items()
                   if key not in ("OPENAI_API_KEY", "ANTHROPIC_API_KEY")}
        return subprocess.run(["node", "evals/harbor/run.mjs", *map(str, args)],
                              cwd=ROOT, env=env, text=True, capture_output=True, timeout=30)

    def staged_run(self):
        output = self.directory / "source"
        result = self.driver("--suite", "command-guidance", "--model", "openai/fixture",
                             "--cases", "long-path", "--output", output)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((output / "manifest.json").is_file())
        return output

    async def recorded_trials(self, primary_pass=True):
        output = self.staged_run()
        for condition in ("guidance", "none"):
            task_dir = output / "tasks" / condition / "long-path"
            request = json.loads((task_dir / "tests" / "case.json").read_text())
            settings = request["settings"]
            good = 'f="/home/eval/.config/remote-environments"\nf="$f/rendered/production/application/settings.yaml"\ncat "$f"'
            command = good if condition == "guidance" and primary_pass else "cat /wrong"
            response = f"```sh\n{command}\n```"
            events = [{"type": "message_end", "message": {"role": "system", "sections": {"preamble": settings["system_prompt"]}}},
                      {"type": "message_end", "message": {"role": "user", "content": [{"type": "text", "text": settings["prompt"]}]}},
                      {"type": "message_end", "message": {"role": "assistant", "stopReason": "stop", "provider": "openai", "model": "fixture",
                       "usage": {"input": 9, "output": 4}, "content": [{"type": "text", "text": response}]}},
                      {"type": "agent_settled"}]
            job = output / "jobs" / condition / "long-path-1"
            paths = TrialPaths(job / "long-path__fixture")
            paths.mkdir()
            (job / "result.json").write_text(json.dumps({"n_total_trials": 1, "stats": {}}))
            (paths.agent_dir / "pi.txt").write_text("\n".join(map(json.dumps, events)))
            verifier = VerifierFactory.create_verifier_from_config(
                VerifierConfig(import_path="evals.harbor.command_verifier:MacOSCommandVerifier"),
                task=Task(task_dir), trial_paths=paths, environment=None)
            reward = await verifier.verify()
            (paths.trial_dir / "result.json").write_text(json.dumps({
                "task_name": "long-path", "exception_info": None,
                "verifier_result": {"rewards": reward.rewards}}))
        return output

    def failed_native_job(self, suite="command-guidance", mode="regression", exception=True):
        tag = f"{suite}-{mode}-{exception}"
        bins = self.directory / ("bin-" + tag)
        bins.mkdir()
        docker = bins / "docker"
        docker.write_text('#!/bin/sh\ncase "$1" in\ncontext) echo unix:///tmp/fixture.sock;;\n'
                          'info) echo \'[{"Name":"compose","Path":"/fixture/docker-compose"}]\';;\nesac\n')
        docker.chmod(0o755)
        calls = self.directory / (tag + "-calls.jsonl")
        harbor = bins / "harbor"
        harbor.write_text(f'''#!{sys.executable}
import json,pathlib,sys
if sys.argv[1] == "--version":
    print("0.24.0")
    raise SystemExit(0)
args=sys.argv
with pathlib.Path({str(calls)!r}).open("a") as f:
    f.write(json.dumps(args)+"\\n")
value=lambda flag: args[args.index(flag)+1]
trial=pathlib.Path(value("--jobs-dir"))/value("--job-name")/"fixture-trial"
trial.mkdir(parents=True)
(trial/"result.json").write_text(json.dumps({{
    "task_name":pathlib.Path(value("--path")).name,
    "exception_info":{{"exception_message":"fixture transport failure"}} if {exception!r} else None
}}))
''')
        harbor.chmod(0o755)
        env = dict(os.environ)
        env.update(PATH=str(bins) + os.pathsep + env["PATH"], OPENAI_API_KEY="fixture-key")
        cases = "long-path,jq" if suite == "command-guidance" else "incidental-bug-report,incidental-monitor-report"
        result = self.driver("--suite", suite, "--model", "openai/fixture", "--mode", mode,
                             "--cases", cases, "--live", "--harbor", str(harbor),
                             "--output", str(self.directory / ("live-" + tag)), env=env)
        return result, calls

    def test_live_driver_stops_after_zero_exit_with_failed_native_trial(self):
        result, calls = self.failed_native_job()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls.read_text().splitlines()), 1,
                         "A native infrastructure failure must stop subsequent paid invocations")

    def test_live_driver_stops_before_next_job_when_evidence_is_incomplete(self):
        for suite in ("command-guidance", "session-naming"):
            for mode in ("regression", "compare"):
                with self.subTest(suite=suite, mode=mode):
                    result, calls = self.failed_native_job(suite, mode, exception=False)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(len(calls.read_text().splitlines()), 1,
                                     "Missing rewards/steps must stop later paid jobs, even without exceptions")

    def test_harbor_cli_preserves_full_prompt_serialization(self):
        source = self.staged_run()
        code = ('import {jobArguments} from "./evals/harbor/invocation.mjs";'
                'import fs from "node:fs"; const root=process.argv[1];'
                'const m=JSON.parse(fs.readFileSync(root+"/manifest.json"));'
                'console.log(JSON.stringify(jobArguments(m,root,m.variants[0],m.cases[0],1)));')
        prepared = subprocess.run(["node", "--input-type=module", "-e", code, str(source)],
                                  cwd=ROOT, text=True, capture_output=True, check=True)
        args = json.loads(prepared.stdout)
        resolved = subprocess.run([str(ROOT / "tmp/harbor-venv/bin/harbor"), *args, "--print-config"],
                                  cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(resolved.returncode, 0, resolved.stderr)
        config = json.loads(resolved.stdout)
        expected = json.loads((source / "tasks/guidance/long-path/tests/case.json").read_text())["settings"]["system_prompt"]
        self.assertEqual(config["agents"][0]["kwargs"]["system_prompt"], expected)

    def test_driver_replays_without_credentials_and_ignores_control_failures(self):
        source = asyncio.run(self.recorded_trials())
        result = self.driver("--replay", source, "--output", self.directory / "replay")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads((self.directory / "replay" / "report.json").read_text())
        self.assertTrue(report["currentPolicyPassed"])
        self.assertEqual(len(report["results"]), 2)
        self.assertEqual((source / "jobs/guidance/long-path-1/long-path__fixture/verifier/assessment.json").read_text(),
                         (self.directory / "replay/jobs/guidance/long-path-1/long-path__fixture/verifier/assessment.json").read_text())

    def test_replay_rejects_incomplete_source_before_regrading(self):
        source = asyncio.run(self.recorded_trials())
        reward = source / "jobs/guidance/long-path-1/long-path__fixture/verifier/reward.json"
        reward.unlink()
        for mode in ("regression", "compare"):
            with self.subTest(mode=mode):
                destination = self.directory / ("missing-reward-" + mode)
                result = self.driver("--replay", source, "--mode", mode, "--output", destination)
                self.assertNotEqual(result.returncode, 0, "Replay must not repair missing source evidence into PASS")
                report = json.loads((destination / "report.json").read_text())
                self.assertTrue(report["errors"])
                self.assertFalse(list(destination.rglob("replay.log")), "Validate the complete source before any regrading")
                self.assertFalse(reward.exists())

    def test_replay_saves_completed_rows_before_later_trace_failure(self):
        source = asyncio.run(self.recorded_trials())
        later = source / "jobs/none/long-path-1/long-path__fixture/agent/pi.txt"
        events = [json.loads(line) for line in later.read_text().splitlines()]
        later.write_text("\n".join(json.dumps(event) for event in events if event["type"] != "agent_settled"))
        destination = self.directory / "partial-replay"
        result = self.driver("--replay", source, "--output", destination)
        self.assertNotEqual(result.returncode, 0)
        report = json.loads((destination / "report.json").read_text())
        self.assertTrue(report["errors"])
        self.assertEqual(len(report["results"]), 1, "A later replay failure must preserve earlier completed outcomes")
        self.assertEqual(report["results"][0]["condition"], "guidance")
        self.assertTrue(report["results"][0]["passed"])
        self.assertEqual((source / "jobs/guidance/long-path-1/long-path__fixture/verifier/assessment.json").read_text(),
                         (destination / "jobs/guidance/long-path-1/long-path__fixture/verifier/assessment.json").read_text())

    def test_trial_collection_rejects_partial_command_rewards(self):
        source = asyncio.run(self.recorded_trials())
        trial = source / "jobs/guidance/long-path-1/long-path__fixture"
        reward_file = trial / "verifier/reward.json"
        rewards = json.loads(reward_file.read_text())
        del rewards["format_policy"]
        reward_file.write_text(json.dumps(rewards))
        code = ('import {collectTrial} from "./evals/harbor/suites.mjs";'
                'import fs from "node:fs"; const [root,trial]=process.argv.slice(1);'
                'const m=JSON.parse(fs.readFileSync(root+"/manifest.json"));'
                'collectTrial(m,root,m.variants[0],trial);')
        result = subprocess.run(["node", "--input-type=module", "-e", code, str(source), str(trial)],
                                cwd=ROOT, text=True, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0, "Incomplete rewards must be infrastructure, not a policy score")

    def test_driver_replay_fails_on_current_policy_regression(self):
        source = asyncio.run(self.recorded_trials(primary_pass=False))
        result = self.driver("--replay", source, "--output", self.directory / "replay")
        self.assertEqual(result.returncode, 1, result.stderr)
        report = json.loads((self.directory / "replay" / "report.json").read_text())
        self.assertFalse(report["currentPolicyPassed"])
        compare = self.driver("--replay", source, "--mode", "compare", "--output", self.directory / "comparison")
        self.assertEqual(compare.returncode, 0, compare.stderr)

    async def test_naming_replay_uses_each_frozen_task_verifier(self):
        from evals.harbor.replay import replay
        for task_name, filename, persisted_name in (
                ("incidental-bug-report", "verify.py", "retained"),
                ("incidental-monitor-report", "base_verify.py", "changed")):
            task = self.directory / task_name
            (task / "tests").mkdir(parents=True)
            (task / "tests" / filename).write_text(
                'def score_trace(events, session, index):\n'
                '    return {"naming": session[0]["name"] == events[0]["name"],\n'
                '            "scorer": "frozen task", "sessionId": "fixture"}\n')
            trial = self.directory / (task_name + "-trial")
            step = trial / "steps/repair-restoration"
            (step / "agent/pi/sessions").mkdir(parents=True)
            (step / "verifier").mkdir()
            (trial / "result.json").write_text(json.dumps({"step_results": [
                {"step_name": "repair-restoration"}]}))
            (step / "agent/pi.txt").write_text(json.dumps({"name": "retained"}) + "\n")
            (step / "agent/pi/sessions/native.jsonl").write_text(json.dumps({"name": persisted_name}))
            (step / "verifier/assessment.json").write_text(json.dumps({"task": True}))
            try:
                await replay("session-naming", task, trial)
            except Exception as error:
                self.fail(f"Replay must execute the frozen scorer for {task_name}: {error}")
            assessment = json.loads((step / "verifier/assessment.json").read_text())
            reward = json.loads((step / "verifier/reward.json").read_text())
            self.assertEqual(assessment["scorer"], "frozen task")
            self.assertEqual(reward["naming"], int(persisted_name == "retained"))
            self.assertTrue(assessment["task"])
            self.assertIn("not rerun", assessment["taskEvidence"])

    def test_driver_rejects_missing_trial_evidence(self):
        source = asyncio.run(self.recorded_trials())
        (source / "jobs/guidance/long-path-1/long-path__fixture/agent/pi.txt").unlink()
        result = self.driver("--replay", source, "--output", self.directory / "replay")
        self.assertNotEqual(result.returncode, 0)
        report = json.loads((self.directory / "replay" / "report.json").read_text())
        self.assertTrue(report["errors"])


if __name__ == "__main__":
    unittest.main()
