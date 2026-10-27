# Short turn status

Status: self-approved.

## Goal and scope
Add the prompt from https://x.com/nateberkopec/status/2114819619513135180 verbatim to the managed global Claude/Codex and Pi instructions. The image reads:

> End any turn that reports on long-running or delegated work with a short status: **Goal**, **Done**, **Next**, **Needs you** (or "nothing").

Keep its conditional scope. Do not require a status on every response. Preserve all existing safeguards. This is a requested addition, not prompt optimization; no effectiveness or token-saving claim is made.

## Approach
Add one bullet near the writing-style rules in each existing base fragment. Claude assembly also supplies Codex through its existing symlink; Pi has its own assembly path.

Alternatives: a separate fragment adds unnecessary structure for one sentence. Editing deployed files loses the change on provisioning and violates repository policy.

## Verification and rollout
Review the transcription against the image and inspect the diff. Use existing Ansible copy/assembly tasks to apply only the changed instructions through `bin/provision`. Confirm the sentence appears once in each deployed global file and that the Codex symlink is intact. Do not add a static prose test. No behavioral eval is needed to substantiate a verbatim transcription, and no unrelated instructions will be removed.
