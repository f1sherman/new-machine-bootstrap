# Provision Sound Effect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace spoken provisioning alerts with the built-in macOS Blow sound.

**Architecture:** Keep notification behavior inside `bin/provision`. A nonfatal helper will play the system sound on macOS and do nothing on Linux.

**Tech Stack:** Bash 3.2, macOS `afplay`

## Global Constraints

- Use `/System/Library/Sounds/Blow.aiff` for success and failure.
- Play notifications only on macOS.
- Notification playback must not change the provisioning exit status.
- Do not add an automated test for this low-impact preference.

---

### Task 1: Replace provisioning speech

**Files:**
- Modify: `bin/provision:151-159,173,374,399`

**Interfaces:**
- Consumes: Existing `mac_os` platform predicate.
- Produces: `play_notification_sound`, a zero-argument, always-successful shell function.

- [ ] **Step 1: Replace the speech helper**

Replace `say_message` with:

```bash
play_notification_sound() {
  mac_os || return 0
  afplay /System/Library/Sounds/Blow.aiff >/dev/null 2>&1 || true
}
```

- [ ] **Step 2: Update all alert call sites**

Replace each success or failure call with:

```bash
play_notification_sound
```

Confirm no `say_message` or spoken provisioning alert remains in `bin/provision`.

- [ ] **Step 3: Validate syntax and whitespace**

Run:

```bash
bash -n bin/provision
git diff --check
```

Expected: both commands exit `0` with no output.

- [ ] **Step 4: Verify the selected sound**

Run:

```bash
afplay /System/Library/Sounds/Blow.aiff
```

Expected: the Blow sound plays and the command exits `0`.

- [ ] **Step 5: Commit the implementation**

Commit only `bin/provision` with the message `Replace spoken provision alerts with sound`.
