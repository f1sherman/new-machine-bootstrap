"""Behavioral checks for the live-trace grader; no model calls required."""
import copy
import importlib.util
import json
import unittest
from pathlib import Path

PATH = Path(__file__).parent / "tasks/incidental-bug-report/tests/verify.py"


def load_score():
    if not PATH.exists():
        return lambda *_: None
    spec = importlib.util.spec_from_file_location("workflow_verifier", PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.score_trace


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


class TraceVerifierTest(unittest.TestCase):
    def test_report_preserves_name_and_records_real_tool_execution(self):
        result = load_score()(*fixture(), 1)
        self.assertIsNotNone(result, "live trace scoring is missing")
        self.assertTrue(result["naming"])
        self.assertEqual(result["calls"][0]["tool"], "create_issue")

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
        events, session = fixture("read")
        session.extend({"type": "message", "message": {"role": "user", "content": "next"}} for _ in range(3))
        session.append({"type": "session_info", "name": "Git branch picker reliability"})
        report = {"id": "issue-1", "title": "Git branch picker", "body": "Outside a repository the exit status is 0."}
        events[3]["result"] = {"content": [{"type": "text", "text": json.dumps([report])}]}
        rename = {"type": "toolCall", "id": "call-2", "name": "set_session_name", "arguments": {"name": "Git branch picker reliability"}}
        events[1]["message"]["content"].append(rename)
        events.insert(4, {"type": "tool_execution_start", "toolCallId": "call-2", "toolName": rename["name"], "args": rename["arguments"]})
        events.insert(5, {"type": "tool_execution_end", "toolCallId": "call-2", "toolName": rename["name"], "isError": False})
        self.assertTrue(load_score()(events, session, 4)["naming"])
        events[2:6] = events[4:6] + events[2:4]
        self.assertFalse(load_score()(events, session, 4)["naming"])

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
