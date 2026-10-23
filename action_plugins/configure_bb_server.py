"""Save a local bb server choice using Ansible's controller-side prompt."""

import json
import os
from pathlib import Path
import tempfile
from urllib.parse import urlsplit

from ansible.errors import AnsiblePromptInterrupt, AnsiblePromptNoninteractive
from ansible.plugins.action import ActionBase
from ansible.utils.display import Display

PERSONAL_URL = "https://bb.brianjohn.com"


def valid_url(value):
    if not isinstance(value, str) or not value or any(c.isspace() for c in value):
        return False
    try:
        url = urlsplit(value)
        return (url.scheme in ("http", "https") and bool(url.hostname)
                and url.username is None and url.password is None
                and not url.query and not url.fragment
                and (url.port is None or 0 < url.port < 65536))
    except ValueError:
        return False


def read_choice(path):
    try:
        document = json.loads(path.read_text())
    except (ValueError, UnicodeError):
        raise ValueError(f"Invalid bb server configuration: {path}") from None
    if not isinstance(document, dict) or "server_url" not in document:
        raise ValueError(f"Invalid bb server configuration: {path}")
    value = document["server_url"]
    if value is not None and not valid_url(value):
        raise ValueError(f"Invalid bb server configuration: {path}")
    return value


def prompt_choice():
    display = Display()
    display.display("Configure bb server (saved for future provisioning runs).\n"
                    f"Personal machines: enter 1 to select {PERSONAL_URL}.\n"
                    "Work machines: press Enter without selecting a URL to keep "
                    "bb's configured connection.\n"
                    "You can also enter another HTTP(S) server URL.", stderr=True)
    while True:
        # Provisioning pipes stdout to its log; stderr keeps the prompt visible.
        display.display("Selection: ", stderr=True)
        try:
            response = display.prompt_until("", private=False,
                                            interrupt_input=(b"\x03", b"\x04"))
        except AnsiblePromptNoninteractive:
            raise ValueError("No saved bb server choice. Run bin/provision --tags bb "
                             "from an interactive terminal to select it once.") from None
        except AnsiblePromptInterrupt:
            raise ValueError("bb server selection cancelled; no choice was saved.") from None
        value = response.decode("utf-8").strip()
        if not value:
            return None
        if value == "1":
            return PERSONAL_URL
        if valid_url(value):
            return value
        display.display("Invalid selection. Use 1, a plain HTTP(S) URL without "
                        "credentials, query, or fragment, or Enter for work.", stderr=True)


def save_choice(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
            temporary = stream.name
            json.dump({"server_url": value}, stream)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


class ActionModule(ActionBase):
    TRANSFERS_FILES = False

    def run(self, tmp=None, task_vars=None):
        result = super().run(tmp, task_vars)
        _, arguments = self.validate_argument_spec(
            argument_spec={"path": {"type": "path", "required": True}})
        if self._task.check_mode:
            return dict(result, changed=False, skipped=True)
        path = Path(arguments["path"])
        try:
            try:
                value = read_choice(path)
                changed = False
            except FileNotFoundError:
                value = prompt_choice()
                save_choice(path, value)
                changed = True
        except (OSError, ValueError) as error:
            return dict(result, failed=True, changed=False, msg=str(error))
        return dict(result, server_url=value, changed=changed)
