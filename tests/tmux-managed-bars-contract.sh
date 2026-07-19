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
RECONCILE_LOCK="tmux-reconcile-status-bars"

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
assert_file_contains "$RECONCILER" \
  'tmux wait-for -L ' \
  "status reconciler acquires a server lock"
assert_file_contains "$RECONCILER" \
  'tmux wait-for -U ' \
  "status reconciler releases its server lock"
assert_file_contains "$RECONCILER" \
  '^trap release_lock EXIT$' \
  "status reconciler releases its lock on exit"

for config in "$LINUX_TMUX_CONF" "$MACOS_TMUX_CONF"; do
  platform="$(basename "$(dirname "$(dirname "$(dirname "$config")")")")"
  for event in client-attached client-session-changed; do
    assert_file_contains "$config" \
      "set-hook -ag ${event} .*tmux-reconcile-status-bars" \
      "$platform config reconciles status on $event"
  done
  assert_file_contains "$config" \
    'set-hook -g client-detached .*tmux-reconcile-status-bars' \
    "$platform config owns status reconciliation on client-detached"
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
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"
detach_reconcilers="$(
  tmux -L "$SOCK" show-hooks -g client-detached 2>/dev/null |
    grep -c 'tmux-reconcile-status-bars' || true
)"
assert_equals "$detach_reconcilers" "1" \
  "repeated config sourcing keeps one client-detached reconciler"

python3 - "$SOCK" "$TEST_HOME" "$RECONCILE_LOCK" "$LINUX_TMUX_CONF" <<'PY'
import fcntl
import os
import pty
import signal
import struct
import subprocess
import sys
import termios
import time

sock, test_home, reconcile_lock, linux_tmux_conf = sys.argv[1:]
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


def assert_statuses_stay(expected_statuses, name, timeout=3.0):
    deadline = time.monotonic() + timeout
    samples = 0
    while time.monotonic() < deadline:
        drain_clients()
        for session, expected in expected_statuses.items():
            actual = status(session)
            if actual != expected:
                raise AssertionError(
                    f"{name}: {session} changed from '{expected}' to '{actual}'"
                )
        samples += 1
        time.sleep(0.05)
    if samples < 2:
        raise AssertionError(f"{name}: insufficient stabilization samples")
    print(f"PASS  {name} ({samples} stable samples over {timeout:.1f}s)")


def client_ttys():
    output = tmux("list-clients", "-F", "#{client_tty}")
    return output.splitlines() if output else []


def start_attach(session, term):
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
    return client


def attach(session, term):
    client = start_attach(session, term)
    wait_until(
        lambda: client["tty"] in client_ttys(),
        f"{term} client attaches to {session}",
        f"client tty {client['tty']} was not listed",
    )
    return client


def request_detach(client):
    tmux("detach-client", "-t", client["tty"])


def finish_detach(client):
    deadline = time.monotonic() + 3
    while client["process"].poll() is None and time.monotonic() < deadline:
        drain_clients()
        time.sleep(0.01)
    client["process"].wait(timeout=0)
    clients.remove(client)
    os.close(client["master"])


def detach(client):
    request_detach(client)
    finish_detach(client)


try:
    assert_status("s", "on", "no clients defaults status on after config load")
    tmux("new-session", "-d", "-s", "unrelated", "sleep", "300")

    tmux("set-option", "-t", "unrelated", "status", "off")
    direct = attach("s", "xterm-256color")
    assert_status("s", "on", "direct-only session keeps status on")
    assert_status("unrelated", "on", "attach reconciles an unrelated session")

    tmux("set-option", "-t", "unrelated", "status", "off")
    detach(direct)
    assert_status("s", "on", "direct client's last detach restores status on")
    assert_status("unrelated", "on", "detach reconciles an unrelated session")

    nested = attach("s", "screen-256color")
    assert_status("s", "off", "screen client makes a nested-only session status off")

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
    assert_status("s", "on", "last nested client detach restores status on")

    for iteration in range(8):
        nested = start_attach("s", "tmux-256color")
        direct = start_attach("s", "xterm-256color")
        wait_until(
            lambda: {nested["tty"], direct["tty"]}.issubset(client_ttys()),
            f"rapid client pair {iteration + 1} attaches",
            "both rapid clients were not listed",
        )
        tmux("set-option", "-t", "s", "status", "off")
        request_detach(direct)
        request_detach(nested)
        finish_detach(direct)
        finish_detach(nested)
    assert_status("s", "on", "rapid attach/detach bursts converge to zero-client status")

    tmux("new-session", "-d", "-s", "switch-source", "sleep", "300")
    tmux("new-session", "-d", "-s", "switch-destination", "sleep", "300")
    switcher = attach("switch-source", "tmux-256color")
    assert_status("switch-source", "off", "switch source starts nested-only")
    tmux("set-option", "-t", "switch-destination", "status", "on")
    tmux("set-option", "-t", "unrelated", "status", "off")
    tmux("switch-client", "-c", switcher["tty"], "-t", "switch-destination")
    assert_status("switch-source", "on", "session switch reconciles the source")
    assert_status("switch-destination", "off", "session switch reconciles the destination")
    assert_status("unrelated", "on", "session switch reconciles an unrelated session")
    detach(switcher)
    assert_status("switch-destination", "on", "switched client's detach restores status")

    for event in ("client-attached", "client-detached", "client-session-changed"):
        tmux("set-hook", "-gu", event)
    direct = attach("s", "xterm-256color")
    tmux("wait-for", "-L", reconcile_lock)
    tmux("set-option", "-t", "s", "status", "off")
    tmux("run-shell", "-b", f"{test_home}/.local/bin/tmux-reconcile-status-bars")
    assert_statuses_stay(
        {"s": "off"},
        "queued reconciliation waits for the server lock",
        timeout=0.5,
    )
    detach(direct)
    nested = attach("s", "tmux-256color")
    tmux("set-option", "-t", "s", "status", "on")
    tmux("wait-for", "-U", reconcile_lock)
    assert_status(
        "s",
        "off",
        "queued reconciliation snapshots clients only after locking",
    )
    detach(nested)
    tmux("set-option", "-t", "unrelated", "status", "off")
    tmux("source-file", linux_tmux_conf)
    assert_status(
        "unrelated",
        "on",
        "restored config hooks finish load reconciliation",
    )

    tmux("new-session", "-d", "-s", "opt-source", "sleep", "300")
    tmux("new-session", "-d", "-s", "opt-destination", "sleep", "300")
    tmux("set-option", "-g", "@managed-bars", "off")
    tmux("set-option", "-t", "opt-source", "status", "off")
    tmux("set-option", "-t", "opt-destination", "status", "on")
    tmux("set-option", "-t", "unrelated", "status", "off")

    direct = attach("opt-source", "xterm-256color")
    assert_statuses_stay(
        {"opt-source": "off", "opt-destination": "on", "unrelated": "off"},
        "@managed-bars=off preserves chosen values after attach",
    )
    detach(direct)
    assert_statuses_stay(
        {"opt-source": "off", "opt-destination": "on", "unrelated": "off"},
        "@managed-bars=off preserves chosen values after detach",
    )

    switcher = attach("opt-source", "screen-256color")
    assert_statuses_stay(
        {"opt-source": "off", "opt-destination": "on", "unrelated": "off"},
        "@managed-bars=off preserves chosen values before session change",
    )
    tmux("switch-client", "-c", switcher["tty"], "-t", "opt-destination")
    assert_statuses_stay(
        {"opt-source": "off", "opt-destination": "on", "unrelated": "off"},
        "@managed-bars=off preserves chosen values after session change",
    )
    detach(switcher)
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
for ((sample = 0; sample < 60; sample++)); do
  actual="$(tmux -L "$SOCK" show-options -v -t "$sid" status)"
  [ "$actual" = "off" ] || fail_case \
    "managed tmux.conf preserves status when @managed-bars off" \
    "status changed from 'off' to '$actual' during stabilization"
  sleep 0.05
done
pass_case "managed tmux.conf preserves status when @managed-bars off (60 stable samples over 3s)"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t s pane-border-status)" "off" \
  "managed tmux.conf preserves pane-border-status when @managed-bars off"

printf '\nAll managed-bars contract checks passed\n'
