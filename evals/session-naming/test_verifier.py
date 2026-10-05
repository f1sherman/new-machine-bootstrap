"""Behavioral checks for the live-trace grader; no model calls required."""
import copy
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

PATH = Path(__file__).parent / "tasks/incidental-bug-report/tests/verify.py"


def load_verifier():
    spec = importlib.util.spec_from_file_location("workflow_verifier", PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_score():
    if not PATH.exists():
        return lambda *_: None
    return load_verifier().score_trace


def fixture(tool="create_issue", name="Ghostty restoration reliability"):
    events = [
        {"type": "session", "id": "same-session"},
        {"type": "message_end", "message": {"role": "assistant", "stopReason": "toolUse",
          "usage": {"input": 10, "output": 2, "cacheRead": 0, "cacheWrite": 0},
          "content": [{"type": "toolCall", "id": "call-1", "name": tool, "arguments": {"title": "Picker fails"}}]}},
        {"type": "tool_execution_start", "toolCallId": "call-1", "toolName": tool, "args": {"title": "Picker fails"}},
        {"type": "tool_execution_end", "toolCallId": "call-1", "toolName": tool, "isError": False},
        {"type": "agent_settled"},
    ]
    session = [
        {"type": "session", "id": "same-session"},
        {"type": "message", "message": {"role": "system", "toolsAdded": [
            {"name": "set_session_name"}, {"name": "create_issue"}, {"name": "read"}, {"name": "bash"}, {"name": "edit"}]}},
        {"type": "message", "message": {"role": "user", "content": "Fix restoration"}},
        {"type": "session_info", "name": name},
        {"type": "message", "message": {"role": "user", "content": "File an incidental issue"}},
    ]
    return events, session


def goal_fixture(batched=False, planned_early=False):
    events, session = fixture("read")
    session.extend({"type": "message", "message": {"role": "user", "content": "next"}} for _ in range(3))
    session.append({"type": "session_info", "name": "Git branch picker reliability"})
    report = {"id": "issue-1", "title": "Git branch picker", "body": "Outside a repository the exit status is 0."}
    events[2]["args"] = {"path": "/workspace/.issues/issues.json"}
    events[1]["message"]["content"][0]["arguments"] = events[2]["args"]
    events[3]["result"] = {"content": [{"type": "text", "text": json.dumps([report])}]}
    rename = {"type": "toolCall", "id": "call-2", "name": "set_session_name", "arguments": {"name": "Git branch picker reliability"}}
    rename_message = copy.deepcopy(events[1])
    rename_message["message"]["content"] = [rename]
    start_message = {"type": "message_start", "message": {"role": "assistant", "content": []}}
    rename_events = [
        {"type": "tool_execution_start", "toolCallId": "call-2", "toolName": rename["name"], "args": rename["arguments"]},
        {"type": "tool_execution_end", "toolCallId": "call-2", "toolName": rename["name"], "isError": False},
    ]
    prefix = [events[0], start_message, events[1], events[2]]
    if batched:
        events[1]["message"]["content"].append(rename)
        tail = [events[3], *rename_events]
    elif planned_early:
        tail = [start_message, rename_message, events[3], *rename_events]
    else:
        tail = [events[3], start_message, rename_message, *rename_events]
    return [*prefix, *tail, events[-1]], session


class TraceVerifierTest(unittest.TestCase):
    def test_report_preserves_name_and_records_real_tool_execution(self):
        result = load_score()(*fixture(), 1)
        self.assertIsNotNone(result, "live trace scoring is missing")
        self.assertTrue(result["naming"])
        self.assertEqual(result["calls"][0]["tool"], "create_issue")

    def report_reward(self, command=None, output=None, is_error=False, after_issue=False):
        events, session = fixture()
        if command is not None:
            args = {"command": command}
            shell = [
                {"type": "message_end", "message": {"role": "assistant", "stopReason": "toolUse",
                 "usage": {"input": 10, "output": 2, "cacheRead": 0, "cacheWrite": 0},
                 "content": [{"type": "toolCall", "id": "shell", "name": "bash", "arguments": args}]}},
                {"type": "tool_execution_start", "toolCallId": "shell", "toolName": "bash", "args": args},
                {"type": "tool_execution_end", "toolCallId": "shell", "toolName": "bash", "isError": is_error,
                 "result": {"content": [{"type": "text", "text": output}]}},
            ]
            position = -1 if after_issue else 1
            events[position:position] = shell
        module = load_verifier()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def sandbox(path):
                return root / str(path).lstrip("/")
            for path, content in {
                "/logs/agent/pi.txt": "\n".join(json.dumps(e) for e in events),
                "/logs/agent/pi/sessions/session.jsonl": "\n".join(json.dumps(e) for e in session),
                "/workspace/.issues/issues.json": json.dumps([{"title": "git-switch-branch", "body": "Exit status 0"}]),
            }.items():
                file = sandbox(path)
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(content)
            sandbox("/logs/verifier").mkdir(parents=True)
            with patch.object(module, "Path", side_effect=sandbox), patch.object(module, "run_check", side_effect=[True, False]):
                module.verify(1)
            return json.loads(sandbox("/logs/verifier/reward.json").read_text())["task"]

    def test_report_requires_shell_reproduction_not_only_issue_text(self):
        self.assertEqual(self.report_reward(), 0)

    def test_report_accepts_matched_shell_error_and_zero_status(self):
        command = 'cd /tmp; bash /workspace/bin/git-switch-branch; printf "status=%s\\n" "$?"'
        output = 'fatal: not a git repository (or any of the parent directories): .git\nstatus=0\n'
        self.assertEqual(self.report_reward(command, output), 1)
        self.assertEqual(self.report_reward(command, output.replace("status=0", "0")), 1)

    def test_report_rejects_other_failure_classes_and_late_reproduction(self):
        command = 'cd /tmp; bash /workspace/bin/git-switch-branch; echo $?'
        output = 'fatal: not a git repository (or any of the parent directories): .git\n0\n'
        cases = [
            (command, output.replace("0\n", "1\n"), False, False),
            (command, "0\n", False, False),
            (command, 'fatal: not a git repository\n', False, False),
            ('bash /workspace/bin/git-switch-branch', output, False, False),
            (command, output, True, False),
            ("cat /workspace/.issues/issues.json", output, False, False),
            (command, output, False, True),
            (command, 'fatal: not a git repository\n100\n', False, False),
        ]
        for args in cases:
            with self.subTest(args=args):
                self.assertEqual(self.report_reward(*args), 0)

    def test_redundant_same_name_call_fails_retention(self):
        events, session = fixture("set_session_name")
        events[2]["args"] = {"name": "Ghostty restoration reliability"}
        events[1]["message"]["content"][0]["arguments"] = events[2]["args"]
        self.assertFalse(load_score()(events, session, 1)["naming"])

    def test_name_change_without_a_tool_call_fails_retention(self):
        events, session = fixture()
        session.append({"type": "session_info", "name": "Branch picker reporting"})
        self.assertFalse(load_score()(events, session, 1)["naming"])

    def test_invalid_streams_raise_instead_of_passing(self):
        original, session = fixture()
        invalid = [original[:-1], [e for e in original if e["type"] != "tool_execution_end"]]
        broken = copy.deepcopy(original)
        broken[1]["message"]["usage"] = {}
        invalid.append(broken)
        broken = copy.deepcopy(original)
        broken[3]["isError"] = True
        invalid.append(broken)
        broken = copy.deepcopy(original)
        broken[0]["id"] = "disconnected-session"
        invalid.append(broken)
        broken = copy.deepcopy(original)
        broken[1]["message"]["content"][0]["id"] = "unexecuted-call"
        invalid.append(broken)
        broken = copy.deepcopy(original)
        broken[1]["message"]["usage"]["input"] = float("nan")
        invalid.append(broken)
        for events in invalid:
            with self.subTest(events=events), self.assertRaises(ValueError):
                load_score()(events, session, 1)

    def test_goal_change_requires_actual_issue_inspection_before_naming(self):
        self.assertTrue(load_score()(*goal_fixture(), 4)["naming"])

    def test_batched_read_and_rename_does_not_count_as_inspection(self):
        self.assertFalse(load_score()(*goal_fixture(batched=True), 4)["naming"])

    def test_later_response_started_before_read_result_fails_inspection(self):
        self.assertFalse(load_score()(*goal_fixture(planned_early=True), 4)["naming"])

    def test_explicit_rename_requires_exact_name_and_persisted_effect(self):
        events, session = fixture("set_session_name")
        session.extend([
            {"type": "message", "message": {"role": "user", "content": "Continue restoration"}},
            {"type": "message", "message": {"role": "user", "content": "Use my exact name"}},
        ])
        events[2]["args"] = {"name": "Ghostty workspace reliability"}
        events[1]["message"]["content"][0]["arguments"] = events[2]["args"]
        session.append({"type": "session_info", "name": "Ghostty workspace reliability"})
        result = load_score()(events, session, 3)
        self.assertTrue(result["naming"])
        events[2]["args"]["name"] = "Restore workspace"
        events[1]["message"]["content"][0]["arguments"] = events[2]["args"]
        self.assertFalse(load_score()(events, session, 3)["naming"])


if __name__ == "__main__":
    unittest.main()
