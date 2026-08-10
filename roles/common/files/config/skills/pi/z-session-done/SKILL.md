---
name: z-session-done
description: Mark the current persistent Pi session done. Use only when the user explicitly asks to mark this session done.
disable-model-invocation: true
---

# Mark Current Session Done

Run this only because the user explicitly requested that the current session be marked done.

1. Confirm `PI_SESSION_FILE` and `PI_SESSION_ID` are non-empty.
2. Run `asr done --source pi --session-id "$PI_SESSION_ID"` exactly once.
3. Report the session ID that was marked done.

Do not accept or substitute another session ID. Do not infer completion from task success, verification, pull-request state, shutdown, inactivity, or goodbye wording.
