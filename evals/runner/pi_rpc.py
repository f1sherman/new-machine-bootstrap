"""Send one prompt to native Pi and record events through orderly shutdown."""
import json
from pathlib import Path
import subprocess
import sys
from threading import Timer


DIALOGS = {"select", "confirm", "input", "editor"}


def run(prompt, output, argv):
    command = {"id": "eval-prompt", "type": "prompt", "message": prompt}
    with Path(output).open("w") as log, subprocess.Popen(
        argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8"
    ) as pi:
        shutdown = Timer(10, pi.kill)
        try:
            pi.stdin.write(json.dumps(command) + "\n")
            pi.stdin.flush()
            accepted = settled = False
            for line in pi.stdout:
                event = json.loads(line)
                if event.get("type") != "message_update":
                    log.write(line)
                    log.flush()
                kind = event.get("type")
                if kind == "extension_ui_request" and event.get("method") in DIALOGS:
                    raise ValueError(f"Unsupported native Pi RPC dialog: {event['method']}")
                if kind == "response" and event.get("id") == command["id"]:
                    accepted = event.get("success") is True and event.get("data", {}).get("disposition") == "started"
                    if not accepted:
                        return False
                if kind == "agent_settled" and not pi.stdin.closed:
                    settled = event.get("aborted") is False
                    pi.stdin.close()
                    shutdown.start()
            return pi.wait(timeout=10) == 0 and accepted and settled
        finally:
            shutdown.cancel()
            if pi.poll() is None:
                pi.kill()


if __name__ == "__main__":
    sys.exit(0 if run(sys.argv[1], sys.argv[2], sys.argv[3:]) else 1)
