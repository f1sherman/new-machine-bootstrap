# Trial OmniWM on Brian's MacBook Pro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install pinned OmniWM on `brian-macbook-pro` and launch it now and at future logins.

**Architecture:** The macOS role gates one focused task file by exact Ansible hostname. That task file installs the Renovate-pinned GitHub release, exposes its CLI, and manages a per-user LaunchAgent. Existing macOS-wide defaults management already enables **Displays have separate Spaces** for OmniWM.

**Tech Stack:** Ansible, YAML, Jinja2, macOS launchd, GitHub Releases, Renovate

**Spec:** `docs/superpowers/specs/2026-08-27-trial-omniwm-design.md`

## Global Constraints

- Install only when `ansible_hostname == 'brian-macbook-pro'`.
- Pin `BarutSRB/OmniWM` release `v0.6.3` through Renovate.
- Install `OmniWM.app` in `/Applications`.
- Link `omniwmctl` into `~/.local/bin`.
- Launch OmniWM now and at later logins with a per-user LaunchAgent.
- Do not configure OmniWM or change Rectangle.
- Keep the existing macOS-wide `com.apple.spaces spans-displays=false`
  management unchanged; do not add a duplicate host-specific setting.
- Preserve `bin/provision --check` without staging, download, extraction,
  application replacement, or launchd mutations.
- Do not add a static automated test that fails the repository's material-value test gate.

---

### Task 1: Host-specific OmniWM installation and login launch

**Files:**
- Modify: `vars/tool_versions.yml`
- Modify: `roles/macos/tasks/main.yml`
- Create: `roles/macos/tasks/install_omniwm.yml`
- Create: `roles/macos/templates/launchd/com.user.omniwm.plist`

**Interfaces:**
- Consumes: `tool_versions.github_releases.omniwm`, Ansible facts `hostname`, `user_dir`, and `user_uid`, and the existing macOS-wide `com.apple.spaces spans-displays=false` default from `roles/macos/vars/defaults.yml`.
- Produces: `/Applications/OmniWM.app`, `~/.local/bin/omniwmctl`, and loaded launchd label `com.user.omniwm`.

- [ ] **Step 1: Confirm the unmanaged baseline**

Run:

```bash
rg -n "omniwm|OmniWM" \
  vars/tool_versions.yml \
  roles/macos/tasks/main.yml \
  roles/macos/tasks  \
  roles/macos/templates/launchd
```

Expected: no managed OmniWM version, installation task, or LaunchAgent exists.

- [ ] **Step 2: Add the Renovate-managed version pin**

Add this entry under `tool_versions.github_releases` in
`vars/tool_versions.yml`:

```yaml
    # renovate: datasource=github-releases depName=BarutSRB/OmniWM
    omniwm: v0.6.3
```

- [ ] **Step 3: Add the host-gated role include**

Add this task to `roles/macos/tasks/main.yml`:

```yaml
- name: Install OmniWM trial on Brian's MacBook Pro
  include_tasks: install_omniwm.yml
  when: ansible_facts['hostname'] == 'brian-macbook-pro'
```

Place it after the general macOS package installation and before unrelated
application configuration.

- [ ] **Step 4: Implement pinned application installation**

Create `roles/macos/tasks/install_omniwm.yml`. It must:

1. Read `/Applications/OmniWM.app/Contents/Info.plist` with
   `/usr/libexec/PlistBuddy`, tolerate a missing app, and set
   `check_mode: false` so this read-only probe executes during check mode.
2. Record whether `CFBundleShortVersionString` differs from the pinned version
   after removing its leading `v`.
3. In check mode, report a changed task when the app is absent or outdated and
   skip all staging, download, extraction, replacement, and launchd mutation
   tasks.
4. Outside check mode, when the version differs, create a staging directory in `/Applications`, download
   `OmniWM-{{ tool_versions.github_releases.omniwm }}.zip` from the matching
   `BarutSRB/OmniWM` release with three retries, and extract it with macOS
   `/usr/bin/ditto -x -k`. Do not use Ansible `unarchive`, which materializes
   AppleDouble `._*` entries and invalidates the signed bundle.
5. Verify the staged app with `/usr/bin/codesign --verify --deep --strict`.
6. Only after extraction, version validation, and signature verification pass,
   stop a loaded OmniWM launchd job, replace the current app bundle, and remove
   the staging directory. If a later task fails, the absent job is the durable
   restart marker for the next provision.
7. After successful replacement, set `omniwm_app_updated: true` for the current
   play so launchd loads the newly installed executable.
8. Create this symlink with `force: true`:

```yaml
src: /Applications/OmniWM.app/Contents/MacOS/omniwmctl
dest: "{{ ansible_facts['user_dir'] }}/.local/bin/omniwmctl"
```

Use an Ansible `block` with `always` cleanup so failed downloads, extraction,
or signature verification do not leave the staging directory behind. Do not
remove the installed app until the new ZIP has downloaded, extracted, matched
the pinned version, and passed strict code-signature verification.

- [ ] **Step 5: Add and manage the LaunchAgent**

Create `roles/macos/templates/launchd/com.user.omniwm.plist` with label
`com.user.omniwm`, one program argument
`/Applications/OmniWM.app/Contents/MacOS/OmniWM`, and `RunAtLoad` set to true.
Do not set `KeepAlive`.

In `install_omniwm.yml`:

1. Before application staging, ensure `~/Library/LaunchAgents` exists and
   template the plist with mode `0644`.
2. Before application staging, run
   `launchctl print gui/{{ ansible_facts['user_uid'] }}/com.user.omniwm` with
   `check_mode: false`, without failing or reporting a change.
3. After the staged app passes version and signature validation, boot out a
   loaded job before replacing the app. Do not stop the job earlier.
4. If only the plist changed, boot out the loaded job after app installation.
   Do not issue a second bootout when an app update already stopped it.
5. Bootstrap the job when it was absent, the template changed, or
   `omniwm_app_updated` is true. This recovers after an interrupted upgrade,
   runs the new process after upgrades, and starts OmniWM during the first
   provision and at later logins.
6. Preserve idempotency: when the app and template are unchanged and the job is
   already loaded, do not boot out or bootstrap the job.

- [ ] **Step 6: Run focused static verification**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
npx --yes --package renovate renovate-config-validator renovate.json
ansible localhost -m setup -a 'filter=ansible_hostname'
git diff --check
```

Expected: all commands exit zero, and the Ansible fact reports
`brian-macbook-pro`.

Run a focused role-only check-mode play with an intentionally different OmniWM
version. Confirm the version and launchd probes execute, the pending update task
reports `changed`, and all staging, download, extraction, replacement, bootout,
and bootstrap tasks are skipped without an undefined staging path. Also check
this lifecycle truth table:

| State | Stop before app replacement | Stop for plist | Load at end |
|---|---:|---:|---:|
| First install, job absent | no | no | yes |
| App update, job loaded | yes | no | yes |
| Plist-only update, job loaded | no | yes | yes |
| App and plist unchanged, job loaded | no | no | no |
| Prior interrupted update, job absent | no | no | yes |

Run the focused signature-preservation test inside the repository:

```bash
rm -rf tmp/omniwm-signature-test
mkdir -p tmp/omniwm-signature-test/extracted
url=https://github.com/BarutSRB/OmniWM/releases/download
curl -fsSL "$url/v0.6.3/OmniWM-v0.6.3.zip" \
  -o tmp/omniwm-signature-test/OmniWM.zip
/usr/bin/ditto -x -k \
  tmp/omniwm-signature-test/OmniWM.zip \
  tmp/omniwm-signature-test/extracted
test -z "$(find tmp/omniwm-signature-test/extracted \
  -name '._*' -print -quit)"
/usr/bin/codesign --verify --deep --strict \
  tmp/omniwm-signature-test/extracted/OmniWM.app
```

Expected: the download and extraction succeed, `find` returns no AppleDouble
files, and `codesign` exits zero.

- [ ] **Step 7: Run end-to-end provisioning**

Run:

```bash
bin/provision
```

Expected: provisioning exits zero and reports OmniWM installation and
LaunchAgent changes on the first run.

- [ ] **Step 8: Verify deployed behavior**

Run:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  /Applications/OmniWM.app/Contents/Info.plist
readlink "$HOME/.local/bin/omniwmctl"
launchctl print "gui/$(id -u)/com.user.omniwm"
pgrep -fl '/Applications/OmniWM.app/Contents/MacOS/OmniWM'
defaults read com.apple.spaces spans-displays
```

Expected: version `0.6.3`, the CLI link targets the app bundle, launchd reports
`com.user.omniwm`, the OmniWM process is present, and `spans-displays` returns
`0`. The existing `0` value means **Displays have separate Spaces** is enabled
and satisfies OmniWM's Mission Control prerequisite. A macOS Accessibility
approval prompt is acceptable and must be reported if it prevents runtime
operation.

- [ ] **Step 9: Commit the implementation**

Run:

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Install OmniWM trial on laptop" \
  vars/tool_versions.yml \
  roles/macos/tasks/main.yml \
  roles/macos/tasks/install_omniwm.yml \
  roles/macos/templates/launchd/com.user.omniwm.plist
```

Expected: one implementation commit is created with no unrelated files.
