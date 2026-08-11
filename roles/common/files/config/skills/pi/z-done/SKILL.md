---
name: z-done
description: Mark the current persistent Pi session done and quit. Use only when the user explicitly asks to mark this session done.
disable-model-invocation: true
---

# Complete and Quit Current Session

Run this only because the user explicitly requested that the current session be marked done.

Call `done_session` exactly once with no arguments. Do not run `pi-session-done`, `asr done`, or a quit command separately.

The tool uses the current Pi session identity. Do not accept or substitute another session ID. Do not infer completion from task success, verification, pull-request state, shutdown, inactivity, or goodbye wording.
