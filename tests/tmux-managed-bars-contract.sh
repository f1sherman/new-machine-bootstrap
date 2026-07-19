#!/usr/bin/env bash
set -euo pipefail

# Contract: managed pane borders and session status bars are enabled by default,
# while @managed-bars=off leaves both values under external ownership. Status
# visibility is reconciled from every real client attached to each session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
LINUX_TMUX_CONF="$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf"
MACOS_TMUX_CONF="$REPO_ROOT/roles/macos/templates/dotfiles/tmux.conf"
PANE_BORDER="$BIN_DIR/tmux-sync-pane-border-status"
RECONCILER="$BIN_DIR/tmux-reconcile-status-bars"

SOCK="nmb-managed-bars-$$"
TEST_HOME="$REPO_ROOT/.tmp/tmux-managed-bars-$$"
mkdir -p "$TEST_HOME/.tmux/plugins/tpm" "$TEST_HOME/.local/bin"
printf '#!/usr/bin/env sh\nexit 0\n' > "$TEST_HOME/.tmux/plugins/tpm/tpm"
chmod +x "$TEST_HOME/.tmux/plugins/tpm/tpm"
ln -s "$RECONCILER" "$TEST_HOME/.local/bin/tmux-reconcile-status-bars"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TEST_HOME"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n      %s\n' "$1" "$2" >&2; exit 1; }
assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}
assert_file_contains() {
  local file="$1" pattern="$2" name="$3"
  if ! grep -Eq "$pattern" "$file"; then
    fail_case "$name" "expected reconciler wiring matching '$pattern' in $file"
  fi
  pass_case "$name"
}
assert_file_not_contains() {
  local file="$1" pattern="$2" name="$3"
  if grep -Eq "$pattern" "$file"; then
    fail_case "$name" "obsolete client-specific status toggle remains in $file"
  fi
  pass_case "$name"
}

[ -x "$RECONCILER" ] || fail_case "status reconciler helper exists" \
  "missing executable $RECONCILER"

for config in "$LINUX_TMUX_CONF" "$MACOS_TMUX_CONF"; do
  platform="$(basename "$(dirname "$(dirname "$(dirname "$config")")")")"
  for event in client-attached client-detached client-session-changed; do
    assert_file_contains "$config" \
      "set-hook -ag ${event} .*tmux-reconcile-status-bars" \
      "$platform config reconciles status on $event"
  done
  assert_file_contains "$config" \
    '^run-shell -b .*tmux-reconcile-status-bars' \
    "$platform config reconciles status at load time"
  assert_file_not_contains "$config" \
    'client_termname.*set status|set status.*client_termname' \
    "$platform config removes per-client status toggles"
done

tmux -L "$SOCK" kill-server 2>/dev/null || true
HOME="$TEST_HOME" tmux -L "$SOCK" new-session -d -s s -x 80 -y 24 sleep 300
sid="$(tmux -L "$SOCK" display-message -p -t s '#{session_id}')"

# pane-border sync
tmux -L "$SOCK" set -gu @managed-bars 2>/dev/null || true
tmux -L "$SOCK" set-window-option -t s pane-border-status off
tmux -L "$SOCK" run-shell "$PANE_BORDER #{pane_id}"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t s pane-border-status)" "bottom" \
  "pane-border sync forces bottom when flag unset"

tmux -L "$SOCK" set -g @managed-bars off
tmux -L "$SOCK" set-window-option -t s pane-border-status off
tmux -L "$SOCK" run-shell "$PANE_BORDER #{pane_id}"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t s pane-border-status)" "off" \
  "pane-border sync no-ops when @managed-bars off"

# A local off value proves that the config-load reconciliation runs; the
# config's global default alone cannot overwrite this session-local value.
tmux -L "$SOCK" set -gu @managed-bars
tmux -L "$SOCK" set-option -t "$sid" status off
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"

python3 - "$SOCK" "$TEST_HOME" <<'PY'
import fcntl
import os
import pty
import signal
import struct
import subprocess
import sys
import termios
import time

sock, test_home = sys.argv[1:]
base_env = os.environ.copy()
base_env["HOME"] = test_home
base_env.pop("TMUX", None)
clients = []


def tmux(*args, check=True):
    result = subprocess.run(
        ["tmux", "-L", sock, *args],
        env=base_env,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def status(session):
    return tmux("show-options", "-v", "-t", session, "status")


def drain_clients():
    for client in clients:
        try:
            while os.read(client["master"], 4096):
                pass
        except (BlockingIOError, OSError):
            pass


def wait_until(predicate, name, detail, timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        drain_clients()
        if predicate():
            print(f"PASS  {name}")
            return
        time.sleep(0.05)
    raise AssertionError(f"{name}: {detail}")


def assert_status(session, expected, name):
    wait_until(
        lambda: status(session) == expected,
        name,
        f"expected status '{expected}', got '{status(session)}'",
    )


def assert_status_stays(session, expected, name, duration=0.5):
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        drain_clients()
        actual = status(session)
        if actual != expected:
            raise AssertionError(
                f"{name}: expected status to remain '{expected}', got '{actual}'"
            )
        time.sleep(0.05)
    print(f"PASS  {name}")


def client_ttys():
    output = tmux("list-clients", "-F", "#{client_tty}")
    return output.splitlines() if output else []


def attach(session, term):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    tty = os.ttyname(slave)
    env = base_env.copy()
    env["TERM"] = term
    process = subprocess.Popen(
        ["tmux", "-L", sock, "attach-session", "-t", session],
        env=env,
        stdin=slave,
        stdout=slave,
        stderr=slave,
        start_new_session=True,
        close_fds=True,
    )
    os.close(slave)
    os.set_blocking(master, False)
    client = {"process": process, "master": master, "tty": tty}
    clients.append(client)
    wait_until(
        lambda: tty in client_ttys(),
        f"{term} client attaches to {session}",
        f"client tty {tty} was not listed",
    )
    return client


def detach(client):
    tmux("detach-client", "-t", client["tty"])
    client["process"].wait(timeout=3)
    clients.remove(client)
    os.close(client["master"])


try:
    assert_status("s", "on", "no clients defaults status on after config load")

    direct = attach("s", "xterm-256color")
    assert_status("s", "on", "direct-only session keeps status on")
    detach(direct)

    nested = attach("s", "tmux-256color")
    assert_status("s", "off", "nested-only session sets status off")

    direct = attach("s", "xterm-256color")
    assert_status("s", "on", "direct client wins in a mixed-client session")

    tmux("set-option", "-t", "s", "status", "off")
    detach(nested)
    assert_status("s", "on", "nested detach reconciles the remaining direct client")

    nested = attach("s", "tmux-256color")
    assert_status("s", "on", "nested attach cannot hide status from a direct client")
    detach(direct)
    assert_status("s", "off", "direct detach reconciles the remaining nested client")

    detach(nested)
    assert_status("s", "on", "last client detach restores status on")

    tmux("new-session", "-d", "-s", "switch-source", "sleep", "300")
    tmux("new-session", "-d", "-s", "switch-destination", "sleep", "300")
    switcher = attach("switch-source", "tmux-256color")
    assert_status("switch-source", "off", "switch source starts nested-only")
    tmux("set-option", "-t", "switch-destination", "status", "on")
    tmux("switch-client", "-c", switcher["tty"], "-t", "switch-destination")
    assert_status("switch-source", "on", "session switch reconciles the source")
    assert_status("switch-destination", "off", "session switch reconciles the destination")
    detach(switcher)
    assert_status("switch-destination", "on", "switched client's detach restores status")

    tmux("set-option", "-g", "@managed-bars", "off")
    tmux("set-option", "-t", "s", "status", "off")
    direct = attach("s", "xterm-256color")
    assert_status_stays(
        "s", "off", "@managed-bars=off preserves status during client transitions"
    )
    detach(direct)
finally:
    for client in list(clients):
        process = client["process"]
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGHUP)
                process.wait(timeout=1)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                process.kill()
        os.close(client["master"])
PY

# managed config load
tmux -L "$SOCK" set -g @managed-bars off
tmux -L "$SOCK" set-option -q -t "$sid" status off
tmux -L "$SOCK" set-window-option -q -t s pane-border-status off
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"
sleep 0.5
assert_equals "$(tmux -L "$SOCK" show-options -v -t "$sid" status)" "off" \
  "managed tmux.conf preserves status when @managed-bars off"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t s pane-border-status)" "off" \
  "managed tmux.conf preserves pane-border-status when @managed-bars off"

printf '\nAll managed-bars contract checks passed\n'
