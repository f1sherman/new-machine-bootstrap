---
name: _generate-codex-auth
description: >
  Maintain a ChatGPT-backed Codex `auth.json` on trusted headless or
  non-interactive hosts. Use when the user wants subscription auth instead of
  API keys, needs to copy Codex auth to a remote machine, or is hitting
  refresh-token rotation / stale `auth.json` failures.
---

# Maintain Codex auth.json

## Source of truth

Official docs:

- `https://developers.openai.com/codex/auth#fallback-authenticate-locally-and-copy-your-auth-cache`
- `https://developers.openai.com/codex/auth/ci-cd-auth`

Codex ChatGPT auth is designed to refresh during normal Codex use. The durable pattern is not "call the refresh API" and not "strip the refresh token"; it is "run Codex and keep the updated `auth.json`."

## Core rule

Keep the full ChatGPT `auth.json`, including `tokens.refresh_token`, on exactly one persistent trusted host or one serialized job stream.

Refresh tokens rotate. If multiple machines or concurrent jobs use the same copy, the first refresh can invalidate the rest.

## Persistent Host Pattern

Use this for headless private hosts and service accounts.

1. On a trusted browser-capable machine, ensure file storage and login:
   ```bash
   printf '%s\n' 'cli_auth_credentials_store = "file"' >> ~/.codex/config.toml
   codex login
   ```

2. Confirm the source file is ChatGPT auth:
   ```bash
   jq -e '.auth_mode == "chatgpt" and (.tokens.refresh_token // "") != ""' ~/.codex/auth.json >/dev/null
   ```

3. Copy the complete file to the target user's Codex home with private perms:
   ```bash
   ssh user@host 'mkdir -p ~/.codex && chmod 700 ~/.codex'
   scp ~/.codex/auth.json user@host:~/.codex/auth.json
   ssh user@host 'chmod 600 ~/.codex/auth.json'
   ```

4. Seed only when missing; do not overwrite the refreshed file from the original seed.

5. Run a real lightweight `codex exec` on a schedule; that normal Codex run is the refresh path.
   ```bash
   HOME=/home/user codex exec --skip-git-repo-check --sandbox read-only 'Reply exactly: OK'
   ```

A weekly run is usually enough; daily is fine for host services.

## Ephemeral Runner Pattern

For ephemeral runners, restore `auth.json`, run Codex, then write the updated `auth.json` back to secure storage.

Required shape:

1. Restore current `auth.json` from secure storage.
2. Run the real Codex job, or a tiny `codex exec` maintenance job.
3. Always persist the resulting `auth.json` after the run.

If step 3 writes back the original seed instead of Codex's updated file, the next run can resurrect stale tokens.

## Verification

`codex login status` only proves Codex can read an auth mode. It does not prove refresh works.

Use:

```bash
jq '{
  auth_mode,
  last_refresh,
  has_access_token: ((.tokens.access_token // "") != ""),
  has_id_token: ((.tokens.id_token // "") != ""),
  has_refresh_token: ((.tokens.refresh_token // "") != "")
}' ~/.codex/auth.json

HOME=/home/user codex exec --skip-git-repo-check --sandbox read-only 'Reply exactly: OK'
```

After a refresh, `auth.json` should retain `auth_mode: "chatgpt"`, token fields, and an updated `last_refresh`.

## Do Not

- Do not strip, blank, or share `tokens.refresh_token` for durable headless auth.
- Do not copy one `auth.json` to multiple independently running machines.
- Do not overwrite a persistent host's refreshed file during provisioning.
- Do not commit plaintext `auth.json`, paste it into tickets, or log it.
- Do not switch to API keys when the user explicitly wants ChatGPT subscription auth.

## Reseeding

Reseed with a fresh full `auth.json` when:

- Codex returns `401` and cannot refresh.
- The refresh token was revoked or expired.
- Another machine rotated the copied token first.
- Secure storage restored an older file.

Preferred reseed on a headless host is `codex login --device-auth` as the target user. If device auth is not usable, run `codex login` on a trusted browser-capable machine and copy the full file again.

## Home-Network Service Pattern

For repo-managed services such as `youtube-monitor`:

- Seed `/opt/<service>/.codex/auth.json` only when missing (`force: false`).
- The live service-owned file is the authority after first run.
- Add a small scheduled `codex exec` refresh job under the service user with `HOME` set to the service home.
- Verify with the refresh job or the real service workflow, not only `codex login status`.
