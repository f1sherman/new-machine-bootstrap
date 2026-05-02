---
name: _generate-codex-auth
description: >
  Generate a portable Codex `auth.json` for deployment to headless / non-interactive
  hosts when logged in via ChatGPT subscription. Use when the user wants to copy
  Codex auth to remote machines, or is hitting the "one host invalidates the other"
  refresh-token-rotation problem.
---

# Generate Portable Codex auth.json

## The problem

ChatGPT-mode `~/.codex/auth.json` contains a `refresh_token` that **rotates on every refresh**. If two hosts share the same `auth.json`, whichever refreshes first invalidates the other. Headless hosts can't re-auth interactively, so they break.

## The fix

Strip `refresh_token` before deploying. Hosts run on the `access_token` only, which is a JWT with a fixed `exp` (~10 days from `last_refresh`). No rotation, no cross-host invalidation. When it expires, re-auth on the primary machine and redeploy.

## Procedure

1. **Refresh on primary first** so the access_token is brand new (gives ~10 days of runway):
   ```bash
   codex login status   # or any command that triggers refresh
   ```
2. **Verify auth_mode is chatgpt** and read the expiry. The JWT payload is base64url-encoded, so substitute `-`/`_` to `+`/`/` before `@base64d`:
   ```bash
   jq -r '.auth_mode' ~/.codex/auth.json   # expect "chatgpt"
   jq -r '.tokens.access_token | split(".") | .[1] | gsub("-";"+") | gsub("_";"/") | @base64d | fromjson | .exp | todate' ~/.codex/auth.json
   ```
3. **Generate portable auth.json** (drops `refresh_token`, keeps everything else). Use `mktemp` so the file is created with mode `0600` from the start — never write the bearer token to a predictable, possibly-symlinked path:
   ```bash
   out=$(mktemp -t codex-auth-portable.XXXXXX)
   jq 'del(.tokens.refresh_token)' ~/.codex/auth.json > "$out"
   echo "$out"
   ```
4. **Deploy** to each headless host at `~/.codex/auth.json` with `0600` perms. Use `scp`, `ansible-playbook --extra-vars`, etc. — whatever the user's provisioning flow is. Delete `$out` after deployment (`shred -u "$out"` if available, else `rm "$out"`).
5. **Tell the user the expiry timestamp** so they know when to redeploy.

## Critical guidance — do NOT hard-code

These creds are short-lived (~10 days) and **must be re-deployed**, not committed.

- Never commit `auth.json` to git (this repo or any repo)
- Never bake into Ansible templates, Dockerfiles, or AMIs
- Never store in `roles/*/files/` or `roles/*/templates/`
- Don't put it in a synced location (iCloud/Dropbox) — sync conflicts will trash it
- Treat each deployment as ephemeral; re-run this skill when tokens expire
- For nmb-style provisioning: copy out-of-band with `scp` after the playbook runs, or pass an absolute path via `ansible-playbook --extra-vars`

If the user asks to "save this for next time" or "add it to the repo", refuse and remind them: rotating creds in version control is a footgun, and these creds rotate every ~10 days anyway.

## Edge cases

- **`auth_mode` is "ApiKey"**: no refresh problem exists. Just copy `auth.json` as-is, or set `OPENAI_API_KEY` env var on the host.
- **`OPENAI_API_KEY` is set alongside tokens**: the API key takes precedence. Consider whether the user actually needs the ChatGPT tokens at all on that host.
- **User wants to *automate* redeployment**: still don't commit creds. Suggest a local script that reads from `~/.codex/auth.json`, strips refresh_token, and pushes via `scp` — run on demand, not from CI.

## Quick reference

| Want | Command |
|------|---------|
| Check auth mode | `jq -r .auth_mode ~/.codex/auth.json` |
| Check access_token expiry | `jq -r '.tokens.access_token \| split(".") \| .[1] \| gsub("-";"+") \| gsub("_";"/") \| @base64d \| fromjson \| .exp \| todate' ~/.codex/auth.json` |
| Generate portable file | `out=$(mktemp -t codex-auth-portable.XXXXXX) && jq 'del(.tokens.refresh_token)' ~/.codex/auth.json > "$out" && echo "$out"` |
| Deploy | `scp "$out" host:'~/.codex/auth.json' && ssh host 'chmod 600 ~/.codex/auth.json' && rm "$out"` |
