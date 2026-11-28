"""Send one prompt to native Pi and record events through orderly shutdown."""
import json
from pathlib import Path
import subprocess
import sys


def run(prompt, output, argv):
    command = {"id": "eval-prompt", "type": "prompt", "message": prompt}
    with Path(output).open("w") as log, subprocess.Popen(
        argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8"
    ) as pi:
        try:
            pi.stdin.write(json.dumps(command) + "\n")
            pi.stdin.flush()
            accepted = settled = False
            for line in pi.stdout:
                event = json.loads(line)
                if event.get("type") != "message_update":
                    log.write(line)
                    log.flush()
                if event.get("type") == "response" and event.get("id") == command["id"]:
                    accepted = event.get("success") is True and event.get("data", {}).get("disposition") == "started"
                    if not accepted:
                        break
                if event.get("type") == "agent_settled":
                    settled = event.get("aborted") is False
                    break
            pi.stdin.close()
            return pi.wait(timeout=10) == 0 and accepted and settled
        finally:
            if pi.poll() is None:
                pi.kill()


if __name__ == "__main__":
    sys.exit(0 if run(sys.argv[1], sys.argv[2], sys.argv[3:]) else 1)
