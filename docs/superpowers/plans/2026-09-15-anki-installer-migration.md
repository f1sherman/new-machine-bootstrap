# Anki Installer Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make provisioning replace the obsolete launcher-based Anki app with the current stable Homebrew cask.

**Architecture:** Add one dedicated Ansible cask task with `state: latest` before the general cask installation task. Homebrew owns application replacement; the task does not touch Anki profile data.

**Tech Stack:** Ansible `homebrew_cask`, Homebrew Cask, macOS

**Spec:** `docs/superpowers/specs/2026-09-15-anki-installer-migration-design.md`

## Global Constraints

- Do not change Anki profiles, decks, add-ons, or user data.
- Do not remove files under `~/Library/Application Support/Anki*`.
- Use the stable Homebrew cask channel.
- Do not add a custom updater or compatibility fallback.
- Automated static-configuration tests are excluded by the repository's material-value test gates; verify the production task end to end instead.

---

### Task 1: Manage the current Anki cask

**Files:**
- Modify: `roles/macos/tasks/main.yml:104`

**Interfaces:**
- Consumes: Ansible's `homebrew_cask` module and the Homebrew `anki` cask.
- Produces: An idempotent provisioning task named `Install current Anki cask`.

- [x] **Step 1: Record the failing production state**

Run:

```bash
brew list --cask --versions anki
defaults read /Applications/Anki.app/Contents/Info \
  CFBundleShortVersionString
test -x /Applications/Anki.app/Contents/MacOS/launcher
```

Expected: Homebrew and the app report `25.09`, while the executable check succeeds. This proves the obsolete launcher installation is present.

- [x] **Step 2: Add the minimal provisioning task**

Insert this task immediately before `Install Brew casks` in `roles/macos/tasks/main.yml`:

```yaml
- name: Install current Anki cask
  homebrew_cask:
    name: anki
    state: latest
```

Do not add Anki to the general `present` list because that state does not upgrade the installed launcher version.

- [x] **Step 3: Validate Ansible syntax**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
```

Expected: exit status 0 and `playbook: playbook.yml`.

- [x] **Step 4: Apply the production task**

Run:

```bash
bin/provision
```

Expected: provisioning succeeds and `Install current Anki cask` upgrades Anki from 25.09 to the current cask release.

- [x] **Step 5: Verify the replacement app end to end**

Run:

```bash
brew list --cask --versions anki
brew info --cask anki --json=v2 | python3 -c \
  'import json,sys; d=json.load(sys.stdin)["casks"][0]; print(d["version"])'
test ! -e /Applications/Anki.app/Contents/MacOS/launcher
open -a Anki
sleep 5
pgrep -x anki
```

Expected: installed and current cask versions match, the old launcher is absent, and the native `anki` process is running.

- [x] **Step 6: Verify idempotence**

Run:

```bash
bin/provision --check
```

Expected: exit status 0 and the Anki task reports no required change.

- [x] **Step 7: Commit the implementation**

Run:

```bash
bash ~/.local/share/skills/_commit/commit.sh \
  -m "Keep Anki on the current installer" \
  roles/macos/tasks/main.yml \
  docs/superpowers/plans/2026-09-15-anki-installer-migration.md
```

Expected: one commit containing the task and this plan.
