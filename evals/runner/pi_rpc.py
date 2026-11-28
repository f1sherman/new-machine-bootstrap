"""Send one prompt to native Pi and record events through orderly shutdown."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time


DIALOGS = {"select", "confirm", "input", "editor"}


def run(prompt, output, argv):
    command = {"id": "eval-prompt", "type": "prompt", "message": prompt}
    with Path(output).open("wb") as log, subprocess.Popen(
        argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE
    ) as pi:
        try:
            pi.stdin.write(json.dumps(command).encode() + b"\n")
            pi.stdin.flush()
            accepted = settled = False
            deadline = None
            partial = b""
            while True:
                if deadline is not None:
                    remaining = max(0, deadline - time.monotonic())
                    if not remaining or not select.select([pi.stdout], [], [], remaining)[0]:
                        raise TimeoutError("Native Pi RPC shutdown timed out")
                chunk = os.read(pi.stdout.fileno(), 65536)
                if not chunk:
                    if partial:
                        raise ValueError("Truncated native Pi RPC event")
                    return pi.wait(timeout=1) == 0 and accepted and settled
                *lines, partial = (partial + chunk).split(b"\n")
                for line in lines:
                    event = json.loads(line)
                    kind = event.get("type")
                    if kind != "message_update":
                        log.write(line + b"\n")
                        log.flush()
                    if deadline is not None and kind in {"agent_start", "turn_start", "agent_settled"}:
                        raise ValueError("Unexpected native Pi turn after settlement")
                    if kind == "extension_ui_request" and event.get("method") in DIALOGS:
                        raise ValueError(f"Unsupported native Pi RPC dialog: {event['method']}")
                    if kind == "response" and event.get("id") == command["id"]:
                        accepted = event.get("success") is True and event.get("data", {}).get("disposition") == "started"
                        if not accepted:
                            return False
                    if kind == "agent_settled":
                        settled = event.get("aborted") is False
                        pi.stdin.close()
                        deadline = time.monotonic() + 10
        finally:
            if pi.poll() is None:
                pi.kill()


if __name__ == "__main__":
    sys.exit(0 if run(sys.argv[1], sys.argv[2], sys.argv[3:]) else 1)
