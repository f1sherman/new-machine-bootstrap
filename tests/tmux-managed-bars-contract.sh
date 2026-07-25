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
      "set-hook -g ${event}\\[90\\] .*tmux-reconcile-status-bars" \
      "$platform config owns indexed status reconciliation on $event"
  done
  assert_file_contains "$config" \
    '^run-shell -b .*tmux-reconcile-status-bars' \
    "$platform config reconciles status at load time"
  base_attach_hook="$(grep -E '^set-hook -g client-attached ' "$config")"
  assert_equals "$(grep -o 'run-shell -b' <<<"$base_attach_hook" | wc -l | tr -d ' ')" "1" \
    "$platform config base client-attached hook uses one background shell"
  assert_equals "$(grep -Ec 'tmux-client-attached.*; PATH=.*\$HOME/\.local/bin/tmux-hook-run \$HOME/\.local/bin/tmux-remote-title publish' <<<"$base_attach_hook" || true)" "1" \
    "$platform config publishes the title after attach maintenance regardless of maintenance status"
  assert_file_not_contains "$config" \
    'tmux-client-attached.*&&.*tmux-remote-title publish' \
    "$platform config does not suppress title publication when attach maintenance fails"
  assert_equals "$(grep -Fc 'PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"' <<<"$base_attach_hook" || true)" "1" \
    "$platform config gives title publication a portable execution PATH"
  assert_equals "$(grep -Fc 'TMUX_HOOK_PANE_ID=#{pane_id}' <<<"$base_attach_hook" || true)" "1" \
    "$platform config preserves the triggering pane ID for title publication"
  assert_file_not_contains "$config" \
    'client_termname.*set status|set status.*client_termname' \
    "$platform config removes per-client status toggles"
done

tmux -L "$SOCK" kill-server 2>/dev/null || true
HOME="$TEST_HOME" tmux -L "$SOCK" new-session -d -s s -x 80 -y 24 sleep 300
HOME="$TEST_HOME" tmux -L "$SOCK" new-window -d -t s: -n second sleep 300
sid="$(tmux -L "$SOCK" display-message -p -t s '#{session_id}')"

# pane-border sync
sync_pane="$(tmux -L "$SOCK" display-message -p -t s:0 '#{pane_id}')"
sync_window="$(tmux -L "$SOCK" display-message -p -t "$sync_pane" '#{window_id}')"
tmux -L "$SOCK" set -gu @managed-bars 2>/dev/null || true
tmux -L "$SOCK" set-window-option -t "$sync_window" pane-border-status off
tmux -L "$SOCK" run-shell "$PANE_BORDER $sync_pane"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t "$sync_window" pane-border-status)" "bottom" \
  "pane-border sync forces bottom when flag unset"

tmux -L "$SOCK" set -g @managed-bars off
tmux -L "$SOCK" set-window-option -t "$sync_window" pane-border-status off
tmux -L "$SOCK" run-shell "$PANE_BORDER $sync_pane"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t "$sync_window" pane-border-status)" "off" \
  "pane-border sync no-ops when @managed-bars off"

# A local off value proves that the config-load reconciliation runs; the
# config's global default alone cannot overwrite this session-local value.
tmux -L "$SOCK" set -gu @managed-bars
tmux -L "$SOCK" set-option -t "$sid" status off
tmux -L "$SOCK" set-hook -g 'client-detached[40]' \
  'set-option -g @unrelated-detach-hook-seen yes'
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"
detach_reconcilers="$(
  tmux -L "$SOCK" show-hooks -g client-detached 2>/dev/null |
    grep -c 'tmux-reconcile-status-bars' || true
)"
assert_equals "$detach_reconcilers" "1" \
  "repeated config sourcing keeps one client-detached reconciler"
unrelated_detach_hooks="$(
  tmux -L "$SOCK" show-hooks -g client-detached 2>/dev/null |
    grep -c '@unrelated-detach-hook-seen' || true
)"
assert_equals "$unrelated_detach_hooks" "1" \
  "repeated config sourcing preserves one unrelated client-detached hook"
attach_hooks="$(tmux -L "$SOCK" show-hooks -g client-attached 2>/dev/null)"
assert_equals "$(grep -c 'tmux-client-attached' <<<"$attach_hooks" || true)" "1" \
  "repeated config sourcing preserves one base client-attached hook"
assert_equals "$(grep -c 'tmux-remote-title publish' <<<"$attach_hooks" || true)" "1" \
  "repeated config sourcing preserves one client-attached title publisher"
assert_equals "$(grep -c 'tmux-reconcile-status-bars' <<<"$attach_hooks" || true)" "1" \
  "repeated config sourcing keeps one indexed client-attached reconciler"
session_change_hooks="$(
  tmux -L "$SOCK" show-hooks -g client-session-changed 2>/dev/null
)"
assert_equals "$(grep -c 'tmux-remote-title publish' <<<"$session_change_hooks" || true)" "1" \
  "repeated config sourcing preserves one base client-session-changed hook"
assert_equals "$(grep -c 'tmux-reconcile-status-bars' <<<"$session_change_hooks" || true)" "1" \
  "repeated config sourcing keeps one indexed client-session-changed reconciler"

python3 - "$SOCK" "$TEST_HOME" "$LINUX_TMUX_CONF" "$PANE_BORDER" <<'PY'
import fcntl
import os
import pathlib
import pty
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import termios
import time

sock, test_home, linux_tmux_conf, pane_border = sys.argv[1:]
base_env = os.environ.copy()
base_env["HOME"] = test_home
base_env.pop("TMUX", None)
clients = []
runtime_dir = pathlib.Path(test_home) / "reconciler-contract"
runtime_dir.mkdir()
test_bin = runtime_dir / "bin"
test_bin.mkdir()
real_tmux = shutil.which("tmux")
tmux_wrapper = test_bin / "tmux"
tmux_wrapper.write_text(
    f'''#!/usr/bin/env bash
if [ "$1" = show-options ] && [ -n "${{RECONCILE_BLOCK_READY:-}}" ]; then
  : > "$RECONCILE_BLOCK_READY"
  while [ ! -e "$RECONCILE_BLOCK_RELEASE" ]; do
    sleep 0.01
  done
fi
if [ "$1" = set-option ] && [ "${{4-}}" = "${{RECONCILE_BLOCK_SET_TARGET:-}}" ]; then
  printf '%s\\n' "$$" > "$RECONCILE_BLOCK_SET_READY"
  while [ ! -e "$RECONCILE_BLOCK_SET_RELEASE" ]; do
    sleep 0.01
  done
fi
exec {shlex.quote(real_tmux)} "$@"
'''
)
tmux_wrapper.chmod(0o755)
launcher = runtime_dir / "launch-reconciler"
launcher.write_text(
    '''#!/usr/bin/env bash
printf '%s\\n' "$$" > "$PID_FILE"
exec "$RECONCILER"
'''
)
launcher.chmod(0o755)
reconciler = pathlib.Path(test_home) / ".local/bin/tmux-reconcile-status-bars"


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


def window_ids(session):
    output = tmux("list-windows", "-t", session, "-F", "#{window_id}")
    return output.splitlines() if output else []


def pane_border_statuses(session):
    return {
        window_id: tmux(
            "show-window-options",
            "-v",
            "-t",
            window_id,
            "pane-border-status",
        )
        for window_id in window_ids(session)
    }


def nested_marker(session):
    return tmux(
        "show-options",
        "-v",
        "-t",
        session,
        "@nested-client-only",
        check=False,
    )


def bars_state(session):
    return status(session), pane_border_statuses(session), nested_marker(session)


def set_bars_state(session, status_value, border_value, marker_value):
    tmux("set-option", "-t", session, "status", status_value)
    for window_id in window_ids(session):
        tmux(
            "set-window-option",
            "-t",
            window_id,
            "pane-border-status",
            border_value,
        )
    if marker_value:
        tmux(
            "set-option",
            "-t",
            session,
            "@nested-client-only",
            marker_value,
        )
    else:
        tmux(
            "set-option",
            "-u",
            "-t",
            session,
            "@nested-client-only",
            check=False,
        )


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


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


def assert_bars(session, expected_status, expected_border, expected_marker, name):
    def matches():
        actual_status, borders, marker = bars_state(session)
        return (
            actual_status == expected_status
            and borders
            and all(value == expected_border for value in borders.values())
            and marker == expected_marker
        )

    wait_until(
        matches,
        name,
        "expected "
        f"status={expected_status}, pane-border-status={expected_border} on every window, "
        f"marker={expected_marker!r}; got {bars_state(session)!r}",
    )


def assert_bars_stay(expected_states, name, timeout=3.0):
    deadline = time.monotonic() + timeout
    samples = 0
    while time.monotonic() < deadline:
        drain_clients()
        for session, expected in expected_states.items():
            actual_status, borders, marker = bars_state(session)
            expected_status, expected_border, expected_marker = expected
            if (
                actual_status != expected_status
                or not borders
                or any(value != expected_border for value in borders.values())
                or marker != expected_marker
            ):
                raise AssertionError(
                    f"{name}: {session} expected {expected!r}, got "
                    f"{(actual_status, borders, marker)!r}"
                )
        samples += 1
        time.sleep(0.05)
    if samples < 2:
        raise AssertionError(f"{name}: insufficient stabilization samples")
    print(f"PASS  {name} ({samples} stable samples over {timeout:.1f}s)")


def sync_pane_border_status(session):
    pane_id = tmux("display-message", "-p", "-t", session, "#{pane_id}")
    tmux(
        "run-shell",
        "-t",
        session,
        f"{shlex.quote(pane_border)} {shlex.quote(pane_id)}",
    )


def client_ttys():
    output = tmux("list-clients", "-F", "#{client_tty}")
    return output.splitlines() if output else []


def start_reconciler(
    label,
    block_ready=None,
    block_release=None,
    block_set_target=None,
    block_set_ready=None,
    block_set_release=None,
):
    pid_file = runtime_dir / f"{label}.pid"
    command = (
        f'PATH={shlex.quote(str(test_bin))}:"$PATH" '
        f'PID_FILE={shlex.quote(str(pid_file))} '
        f'RECONCILER={shlex.quote(str(reconciler))} '
    )
    if block_ready is not None:
        command += f'RECONCILE_BLOCK_READY={shlex.quote(str(block_ready))} '
        command += f'RECONCILE_BLOCK_RELEASE={shlex.quote(str(block_release))} '
    if block_set_target is not None:
        command += f'RECONCILE_BLOCK_SET_TARGET={shlex.quote(block_set_target)} '
        command += f'RECONCILE_BLOCK_SET_READY={shlex.quote(str(block_set_ready))} '
        command += f'RECONCILE_BLOCK_SET_RELEASE={shlex.quote(str(block_set_release))} '
    command += shlex.quote(str(launcher))
    tmux("run-shell", "-b", command)
    wait_until(
        lambda: pid_file.exists() and pid_file.read_text().strip().isdigit(),
        f"{label} reconciler starts",
        f"PID file {pid_file} was not populated",
    )
    return int(pid_file.read_text().strip())


def wait_for_process_exit(pid, name):
    wait_until(
        lambda: not process_alive(pid),
        name,
        f"process {pid} did not exit",
    )


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
    if len(window_ids("s")) < 2:
        raise AssertionError("nested topology requires at least two existing windows")
    print("PASS  nested topology has at least two existing windows")
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "no clients show both managed bars with marker unset",
    )
    tmux("new-session", "-d", "-s", "unrelated", "sleep", "300")

    tmux("set-option", "-t", "unrelated", "status", "off")
    direct = attach("s", "xterm-256color")
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "direct-only session shows both managed bars with marker unset",
    )
    assert_status("unrelated", "on", "attach reconciles an unrelated session")

    tmux("set-option", "-t", "unrelated", "status", "off")
    detach(direct)
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "direct client's last detach restores both bars with marker unset",
    )
    assert_status("unrelated", "on", "detach reconciles an unrelated session")
    wait_until(
        lambda: tmux("show-options", "-gv", "@unrelated-detach-hook-seen") == "yes",
        "unrelated client-detached hook still runs",
        "unrelated detach hook did not set its marker",
    )

    nested = attach("s", "screen-256color")
    assert_bars(
        "s",
        "off",
        "off",
        "1",
        "nested-only session hides both bars on every window and sets marker",
    )
    sync_pane_border_status("s")
    assert_bars(
        "s",
        "off",
        "off",
        "1",
        "pane-label refresh keeps nested-only pane labels hidden",
    )

    direct = attach("s", "xterm-256color")
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "mixed direct and nested clients show both bars with marker unset",
    )
    sync_pane_border_status("s")
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "pane-label refresh restores direct-client pane labels",
    )

    tmux("set-option", "-t", "s", "status", "off")
    detach(nested)
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "nested detach reconciles the remaining direct client",
    )

    nested = attach("s", "tmux-256color")
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "nested attach cannot hide bars from a direct client",
    )
    detach(direct)
    assert_bars(
        "s",
        "off",
        "off",
        "1",
        "direct detach hides both bars for the remaining nested client",
    )

    detach(nested)
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "last nested client detach restores both bars with marker unset",
    )

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
        tmux("set-hook", "-gu", f"{event}[90]")
    barrier_pid = start_reconciler("pre-kill-barrier")
    wait_until(
        lambda: not process_alive(barrier_pid),
        "earlier background reconciliations drain before SIGKILL coverage",
        f"process {barrier_pid} did not exit",
        timeout=10.0,
    )
    owner_ready = runtime_dir / "owner.ready"
    owner_release = runtime_dir / "owner.release"
    owner_pid = start_reconciler(
        "owner",
        block_ready=owner_ready,
        block_release=owner_release,
    )
    wait_until(
        owner_ready.exists,
        "lock owner reaches managed-state inspection",
        "lock owner did not advance beyond acquisition",
    )
    set_bars_state("s", "off", "off", "stale-marker")
    queued_pid = start_reconciler("queued-after-kill")
    assert_bars_stay(
        {"s": ("off", "off", "stale-marker")},
        "queued reconciliation leaves all managed state untouched behind the lock owner",
        timeout=0.5,
    )
    if not process_alive(queued_pid):
        raise AssertionError("queued reconciler exited while lock owner was alive")
    print("PASS  queued reconciler remains alive behind the lock owner")
    os.kill(owner_pid, signal.SIGKILL)
    owner_release.touch()
    wait_for_process_exit(owner_pid, "SIGKILLed lock owner exits")
    wait_for_process_exit(
        queued_pid,
        "queued reconciler acquires after owner SIGKILL",
    )
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "queued reconciler converges all managed state after owner SIGKILL",
    )

    set_bars_state("s", "off", "off", "stale-marker")
    successor_pid = start_reconciler("post-kill-successor")
    wait_for_process_exit(
        successor_pid,
        "subsequent reconciler acquires after owner SIGKILL",
    )
    assert_bars(
        "s",
        "on",
        "bottom",
        "",
        "subsequent reconciler converges all managed state after owner SIGKILL",
    )

    direct = attach("s", "xterm-256color")
    target_sid = tmux("display-message", "-p", "-t", "s", "#{session_id}")
    tmux("set-option", "-t", "s", "status", "off")
    mutation_ready = runtime_dir / "mutation.ready"
    mutation_release = runtime_dir / "mutation.release"
    mutation_owner_pid = start_reconciler(
        "mutation-owner",
        block_set_target=target_sid,
        block_set_ready=mutation_ready,
        block_set_release=mutation_release,
    )
    wait_until(
        lambda: mutation_ready.exists()
        and mutation_ready.read_text().strip().isdigit(),
        "lock owner reaches an in-flight status mutation",
        "set-option child did not publish its PID after the owner snapshot",
    )
    mutation_child_pid = int(mutation_ready.read_text().strip())
    os.kill(mutation_owner_pid, signal.SIGKILL)
    wait_for_process_exit(
        mutation_owner_pid,
        "in-flight mutation owner exits on SIGKILL",
    )
    detach(direct)
    nested = attach("s", "tmux-256color")
    mutation_queued_pid = start_reconciler("queued-behind-mutation")
    assert_bars_stay(
        {"s": ("off", "bottom", "")},
        "queued reconciliation leaves all managed state untouched behind the in-flight mutation child",
        timeout=0.5,
    )
    queued_behind_mutation = process_alive(mutation_queued_pid)
    mutation_release.touch()
    wait_for_process_exit(
        mutation_child_pid,
        "orphaned status mutation child exits",
    )
    wait_for_process_exit(
        mutation_queued_pid,
        "queued reconciler finishes after mutation child",
    )
    if not queued_behind_mutation:
        raise AssertionError(
            "queued reconciler was not serialized with the in-flight "
            f"mutation child; final status is {status('s')}"
        )
    print("PASS  queued reconciler remains behind the in-flight mutation child")
    assert_bars(
        "s",
        "off",
        "off",
        "1",
        "queued reconciler repairs all stale managed state after owner SIGKILL",
    )

    set_bars_state("s", "on", "bottom", "")
    mutation_successor_pid = start_reconciler("post-mutation-successor")
    wait_for_process_exit(
        mutation_successor_pid,
        "fresh successor acquires after mutation child",
    )
    assert_bars(
        "s",
        "off",
        "off",
        "1",
        "fresh successor converges all managed state after mutation child",
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
    tmux("set-window-option", "-t", "opt-source", "pane-border-status", "off")
    tmux("set-option", "-t", "opt-source", "@nested-client-only", "keep-source")
    tmux("set-option", "-t", "opt-destination", "status", "on")
    tmux("set-window-option", "-t", "opt-destination", "pane-border-status", "bottom")
    tmux("set-option", "-t", "opt-destination", "@nested-client-only", "1")
    tmux("set-option", "-t", "unrelated", "status", "off")
    tmux("set-window-option", "-t", "unrelated", "pane-border-status", "top")
    tmux("set-option", "-u", "-t", "unrelated", "@nested-client-only", check=False)
    opted_out_states = {
        "opt-source": ("off", "off", "keep-source"),
        "opt-destination": ("on", "bottom", "1"),
        "unrelated": ("off", "top", ""),
    }

    direct = attach("opt-source", "xterm-256color")
    assert_bars_stay(
        opted_out_states,
        "@managed-bars=off preserves bars and markers after attach",
    )
    detach(direct)
    assert_bars_stay(
        opted_out_states,
        "@managed-bars=off preserves bars and markers after detach",
    )

    switcher = attach("opt-source", "screen-256color")
    assert_bars_stay(
        opted_out_states,
        "@managed-bars=off preserves bars and markers before session change",
    )
    tmux("switch-client", "-c", switcher["tty"], "-t", "opt-destination")
    assert_bars_stay(
        opted_out_states,
        "@managed-bars=off preserves bars and markers after session change",
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
