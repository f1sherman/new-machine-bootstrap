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

Replace `refresh_token` with a placeholder string before deploying. The Codex auth loader requires the `refresh_token` field to exist (verified — deleting it errors out with `missing field refresh_token` on every command), but the value can be bogus. Hosts then run on the static `access_token`, which is a JWT with a fixed `exp` (~10 days from `last_refresh`). No machine can mutate the bundle, so they all stay in sync until the access_token expires. Then re-auth on the primary and redeploy.

Refresh attempts will fail on the headless hosts (codex prints something like "Your access token could not be refreshed"), but the static access_token works for normal calls until `exp`.

## Procedure

1. **Check current expiry on the primary**. Decode and print `exp`. If it's not far enough in the future for your purposes, run `codex login` (the full browser OAuth flow) on the primary to mint a fresh ~10-day token. `codex login status` does **not** trigger a refresh — it only reads the active mode.
   ```bash
   jq -r '.auth_mode' ~/.codex/auth.json   # expect "chatgpt"
   jq -r '
     .tokens.access_token
     | split(".") | .[1]
     | gsub("-";"+") | gsub("_";"/")
     | @base64d | fromjson | .exp | todate
   ' ~/.codex/auth.json
   ```
   If runway is too short, run `codex login` and re-check. (The JWT payload is base64url, so the `gsub` calls translate `-`/`_` to `+`/`/` before `@base64d`, which only handles standard base64.)

2. **Generate portable auth.json**. Replace `refresh_token` with an empty string (do **not** delete the field). Use `mktemp -t` so the file is created with mode `0600` from the start — never write the bearer token to a predictable, possibly-symlinked path:
   ```bash
   out=$(mktemp -t codex-auth-portable.XXXXXX)
   jq '.tokens.refresh_token = ""' ~/.codex/auth.json > "$out"
   echo "$out"
   ```

3. **Deploy** to each headless host at `~/.codex/auth.json` with `0600` perms. Single-quote remote paths so `~` expands on the target host, not locally:
   ```bash
   scp "$out" host:'~/.codex/auth.json' && ssh host 'chmod 600 ~/.codex/auth.json'
   rm "$out"   # or `shred -u "$out"` if available
   ```

4. **Tell the user the expiry timestamp** so they know when to redeploy.

5. **Sanity-check on a remote host** (optional but recommended after the first deploy):
   ```bash
   ssh host 'codex login status'   # expect: "Logged in using ChatGPT"
   ```

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
- **User wants to *automate* redeployment**: still don't commit creds. Suggest a local script that reads from `~/.codex/auth.json`, neutralizes refresh_token, and pushes via `scp` — run on demand, not from CI.

## Quick reference

| Want | Command |
|------|---------|
| Check auth mode | `jq -r .auth_mode ~/.codex/auth.json` |
| Check access_token expiry | `jq -r '.tokens.access_token \| split(".") \| .[1] \| gsub("-";"+") \| gsub("_";"/") \| @base64d \| fromjson \| .exp \| todate' ~/.codex/auth.json` |
| Force fresh ~10-day token | `codex login` (browser OAuth) — `codex login status` does not refresh |
| Generate portable file | `out=$(mktemp -t codex-auth-portable.XXXXXX) && jq '.tokens.refresh_token = ""' ~/.codex/auth.json > "$out" && echo "$out"` |
| Deploy | `scp "$out" host:'~/.codex/auth.json' && ssh host 'chmod 600 ~/.codex/auth.json' && rm "$out"` |
