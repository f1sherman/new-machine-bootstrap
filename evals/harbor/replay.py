"""Regrade copied artifacts without a provider, preserving original evidence."""

import argparse
import asyncio
import importlib.util
import json
from pathlib import Path

from harbor.models.task.task import Task
from harbor.models.trial.paths import TrialPaths
from evals.harbor.command_verifier import MacOSCommandVerifier

ROOT = Path(__file__).resolve().parents[2]


async def replay(suite, task_dir, trial_dir):
    if suite == "command-guidance":
        verifier = MacOSCommandVerifier(task=Task(task_dir), trial_paths=TrialPaths(trial_dir), environment=None)
        await verifier.verify()
        return
    spec = importlib.util.spec_from_file_location(
        "naming_verifier", ROOT / "evals/session-naming/tasks/incidental-bug-report/tests/verify.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = json.loads((trial_dir / "result.json").read_text())
    for index, step in enumerate(result["step_results"]):
        directory = trial_dir / "steps" / step["step_name"]
        assessment_file = directory / "verifier/assessment.json"
        old = json.loads(assessment_file.read_text())
        events = [json.loads(line) for line in (directory / "agent/pi.txt").read_text().splitlines() if line.startswith("{")]
        sessions = list((directory / "agent/pi/sessions").glob("*.jsonl"))
        if len(sessions) != 1:
            raise ValueError("Expected exactly one native session")
        session = [json.loads(line) for line in sessions[0].read_text().splitlines() if line.strip()]
        fresh = module.score_trace(events, session, index)
        # Script verification requires the original container. Trace replay does
        # not pretend to rerun it; preserve and label the captured task outcome.
        fresh["task"] = old["task"]
        fresh["taskEvidence"] = "captured behavioral checks; not rerun during trace replay"
        assessment_file.write_text(json.dumps(fresh, indent=2) + "\n")
        rewards = {"reward": int(fresh["task"] and fresh["naming"]),
                   "task": int(fresh["task"]), "naming": int(fresh["naming"])}
        (directory / "verifier/reward.json").write_text(json.dumps(rewards) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=("command-guidance", "session-naming"), required=True)
    parser.add_argument("--task", type=Path, required=True)
    parser.add_argument("--trial", type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(replay(args.suite, args.task, args.trial))
