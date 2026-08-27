# Trial OmniWM on Brian's MacBook Pro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install pinned OmniWM on `brian-macbook-pro` and launch it now and at future logins.

**Architecture:** The macOS role gates one focused task file by exact Ansible hostname. That task file installs the Renovate-pinned GitHub release, exposes its CLI, and manages a per-user LaunchAgent.

**Tech Stack:** Ansible, YAML, Jinja2, macOS launchd, GitHub Releases, Renovate

**Spec:** `docs/superpowers/specs/2026-08-27-trial-omniwm-design.md`

## Global Constraints

- Install only when `ansible_hostname == 'brian-macbook-pro'`.
- Pin `BarutSRB/OmniWM` release `v0.6.3` through Renovate.
- Install `OmniWM.app` in `/Applications`.
- Link `omniwmctl` into `~/.local/bin`.
- Launch OmniWM now and at later logins with a per-user LaunchAgent.
- Do not configure OmniWM or change Rectangle.
- Do not add a static automated test that fails the repository's material-value test gate.

---

### Task 1: Host-specific OmniWM installation and login launch

**Files:**
- Modify: `vars/tool_versions.yml`
- Modify: `roles/macos/tasks/main.yml`
- Create: `roles/macos/tasks/install_omniwm.yml`
- Create: `roles/macos/templates/launchd/com.user.omniwm.plist`

**Interfaces:**
- Consumes: `tool_versions.github_releases.omniwm` and Ansible facts `hostname`, `user_dir`, and `user_uid`.
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
   `/usr/libexec/PlistBuddy` and tolerate a missing app.
2. Compare `CFBundleShortVersionString` with the pinned version after removing
   its leading `v`.
3. When different, create a staging directory in `/Applications`, download
   `OmniWM-{{ tool_versions.github_releases.omniwm }}.zip` from the matching
   `BarutSRB/OmniWM` release with three retries, extract it, replace the current
   app bundle, and remove the staging directory.
4. Create this symlink with `force: true`:

```yaml
src: /Applications/OmniWM.app/Contents/MacOS/omniwmctl
dest: "{{ ansible_facts['user_dir'] }}/.local/bin/omniwmctl"
```

Use an Ansible `block` with `always` cleanup so failed downloads or extraction
do not leave the staging directory behind. Do not remove the installed app
until the new ZIP has downloaded and extracted successfully.

- [ ] **Step 5: Add and manage the LaunchAgent**

Create `roles/macos/templates/launchd/com.user.omniwm.plist` with label
`com.user.omniwm`, one program argument
`/Applications/OmniWM.app/Contents/MacOS/OmniWM`, and `RunAtLoad` set to true.
Do not set `KeepAlive`.

In `install_omniwm.yml`:

1. Ensure `~/Library/LaunchAgents` exists.
2. Template the plist with mode `0644` and register whether it changed.
3. Check `launchctl print gui/{{ ansible_facts['user_uid'] }}/com.user.omniwm`
   without failing or reporting a change.
4. Boot out a loaded job only when the template changed.
5. Bootstrap the job when it was absent or the template changed. This starts
   OmniWM during the first provision and at later logins.

- [ ] **Step 6: Run focused static verification**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
npx --yes renovate-config-validator renovate.json
ansible localhost -m setup -a 'filter=ansible_hostname'
git diff --check
```

Expected: all commands exit zero, and the Ansible fact reports
`brian-macbook-pro`.

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
```

Expected: version `0.6.3`, the CLI link targets the app bundle, launchd reports
`com.user.omniwm`, and the OmniWM process is present. A macOS Accessibility
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
