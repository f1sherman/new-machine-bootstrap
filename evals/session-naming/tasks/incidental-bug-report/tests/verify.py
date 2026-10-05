"""Hidden Harbor verifier for real work and Pi naming events."""
import json
import subprocess
import sys
from pathlib import Path

STEPS = ("repair-restoration", "report-incidental-bug", "continue-restoration", "explicit-rename", "change-goal")
EXPLICIT_NAME = "Ghostty workspace reliability"


def read_issue_result(end):
    if end.get("isError"):
        return False
    result = end.get("result", {})
    values = [result.get("details")]
    for block in result.get("content", []):
        if block.get("type") == "text":
            try:
                values.append(json.loads(block["text"]))
            except (ValueError, TypeError):
                pass
    while values:
        value = values.pop()
        if isinstance(value, list):
            values.extend(value)
        elif isinstance(value, dict) and value.get("id") == "issue-1" and value.get("title") and value.get("body"):
            return True
    return False


def score_trace(events, session, index):
    if not events or events[0].get("type") != "session":
        raise ValueError("Missing JSON session header")
    if not session or events[0]["id"] != session[0].get("id"):
        raise ValueError("Native session continuity failed")
    if not any(e.get("type") == "agent_settled" for e in events):
        raise ValueError("Incomplete Pi event stream")
    declared = set()
    users = []
    name = ""
    before = ""
    for entry in session:
        if entry.get("type") == "session_info":
            name = entry.get("name", "")
        message = entry.get("message", {})
        if message.get("role") == "system":
            declared.update(t["name"] for t in message.get("toolsAdded", []))
            declared.difference_update(message.get("toolsRemoved", []))
        if message.get("role") == "user":
            users.append(message)
            if len(users) == index + 1:
                before = name
    if len(users) != index + 1:
        raise ValueError("Wrong number of real user turns; resume was not honored")
    if not {"set_session_name", "create_issue", "read", "edit", "bash"} <= declared:
        raise ValueError("Missing production naming or normal workflow tools")
    messages = [e["message"] for e in events if e.get("type") == "message_end" and e.get("message", {}).get("role") == "assistant"]
    if not messages or any(m.get("stopReason") in ("error", "aborted") for m in messages):
        raise ValueError("Missing or failed model response")
    usage = {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
    for message in messages:
        value = message.get("usage", {})
        if any(type(value.get(key)) is not int or value[key] < 0 for key in usage):
            raise ValueError("Missing provider usage")
        for key in usage:
            usage[key] += value[key]
    if usage["input"] + usage["cacheRead"] + usage["cacheWrite"] <= 0:
        raise ValueError("Missing input usage")
    starts = [e for e in events if e.get("type") == "tool_execution_start"]
    ends = [e for e in events if e.get("type") == "tool_execution_end"]
    planned = [block for message in messages for block in message.get("content", []) if block.get("type") == "toolCall"]
    planned_at = {}
    response_start = None
    result_positions = {}
    for position, event in enumerate(events):
        if event.get("type") == "message_start" and event.get("message", {}).get("role") == "assistant":
            response_start = position
        elif event.get("type") == "message_end" and event.get("message", {}).get("role") == "assistant":
            for block in event["message"].get("content", []):
                if block.get("type") == "toolCall":
                    planned_at[block["id"]] = response_start
            response_start = None
        elif event.get("type") == "tool_execution_end":
            result_positions[event["toolCallId"]] = position
    ids = [s["toolCallId"] for s in starts]
    if len(set(ids)) != len(ids) or sorted(ids) != sorted(e["toolCallId"] for e in ends) or sorted(ids) != sorted(p["id"] for p in planned):
        raise ValueError("Incomplete or inconsistent tool execution")
    for start in starts:
        end = next(e for e in ends if e["toolCallId"] == start["toolCallId"])
        plan = next(p for p in planned if p["id"] == start["toolCallId"])
        if plan["name"] != start["toolName"] or plan["arguments"] != start["args"] or end["toolName"] != start["toolName"]:
            raise ValueError("Tool execution disagrees with actual assistant call")
        if end.get("isError") and start["toolName"] in ("set_session_name", "create_issue", "get_issue"):
            raise ValueError("Naming or issue tool failed")
    calls = [{"tool": e["toolName"], "args": e["args"]} for e in starts]
    naming_calls = [c for c in calls if c["tool"] == "set_session_name"]
    valid_name = isinstance(name, str) and 0 < len(name.strip()) <= 80 and "\n" not in name
    inspected = [i for i, start in enumerate(starts) if read_issue_result(next(e for e in ends if e["toolCallId"] == start["toolCallId"]))]
    if index in (1, 2):
        naming = valid_name and not naming_calls and name == before
    else:
        naming = valid_name and len(naming_calls) == 1 and naming_calls[0]["args"].get("name") == name
        if index == 3:
            naming = naming and name == EXPLICIT_NAME
        if index == 4:
            rename = next((start for start in starts if start["toolName"] == "set_session_name"), None)
            rename_planned_at = planned_at.get(rename["toolCallId"]) if rename else None
            inspected_before_planning = rename_planned_at is not None and any(
                result_positions[starts[i]["toolCallId"]] < rename_planned_at for i in inspected
            )
            naming = naming and bool(before) and name != before and inspected_before_planning
    return {"naming": bool(naming), "inspectedIssue": bool(inspected), "beforeName": before, "name": name, "calls": calls, "usage": usage, "firstRequestInput": sum(messages[0]["usage"][key] for key in ("input", "cacheRead", "cacheWrite")), "sessionId": session[0]["id"]}


def run_check(command, destination):
    result = subprocess.run(command, cwd="/workspace", capture_output=True, text=True, timeout=40)
    Path(destination).write_text(result.stdout + result.stderr)
    return result.returncode == 0


def verify(index):
    events = []
    for line in Path("/logs/agent/pi.txt").read_text().split("\n"):
        if line.startswith("{"):
            events.append(json.loads(line))
    files = list(Path("/logs/agent/pi/sessions").glob("*.jsonl"))
    if len(files) != 1:
        raise ValueError("Expected exactly one native session file")
    session = [json.loads(line) for line in files[0].read_text().split("\n") if line.strip()]
    assessment = score_trace(events, session, index)
    restored = run_check(["ruby", "/tests/restoration.rb"], "/logs/verifier/restoration.txt")
    task = restored
    if index == 1:
        issues = json.loads(Path("/workspace/.issues/issues.json").read_text())
        reports = [issue for issue in issues if "git-switch-branch" in issue["title"] + issue["body"] and "0" in issue["body"]]
        task = restored and len(reports) == 1 and not run_check(["bash", "/tests/branch-picker.sh"], "/logs/verifier/branch-picker.txt")
        task = task and any(c["tool"] == "create_issue" for c in assessment["calls"])
    elif index == 2:
        readme = Path("/workspace/README.md").read_text().lower()
        task = restored and "manifest" in readme and ("selected" in readme or "selection" in readme) and len(readme) > 150
        task = task and any(c["tool"] in ("edit", "write", "bash") for c in assessment["calls"])
    elif index == 4:
        task = restored and run_check(["bash", "/tests/branch-picker.sh"], "/logs/verifier/branch-picker.txt")
        task = task and assessment["inspectedIssue"]
    assessment["task"] = bool(task)
    Path("/logs/verifier/assessment.json").write_text(json.dumps(assessment, indent=2) + "\n")
    reward = {"reward": int(task and assessment["naming"]), "task": int(task), "naming": int(assessment["naming"])}
    Path("/logs/verifier/reward.json").write_text(json.dumps(reward) + "\n")


if __name__ == "__main__":
    verify(STEPS.index(sys.argv[1]))
