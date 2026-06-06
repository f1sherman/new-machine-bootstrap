---
name: macos-keychain-secrets
description: >
  Use when setting up or debugging local macOS Keychain secrets for app
  integrations, CLI tokens, or provider credentials.
---

# macOS Keychain Secrets

Use this skill when setting up or debugging local macOS Keychain secrets for
app integrations, CLI tokens, or provider credentials.

## Diagnose

Check the keychain search list, default keychain, and login keychain file:

```bash
security list-keychains
security default-keychain
test -f "$HOME/Library/Keychains/login.keychain-db"
```

The default keychain should be the file
`~/Library/Keychains/login.keychain-db`, not the directory
`~/Library/Keychains`.

## Prefer Existing App Wrappers

Before direct `security` commands, search for app-specific Keychain wrappers
and service/account naming:

```bash
rg -n "Keychain|add-generic-password|find-generic-password|keychain" .
```

Use the wrapper if available.

## Direct Security Commands

Always pass the explicit keychain path. For lookup commands, pass it as the
final argument:

```bash
security find-generic-password -s "$service" -a "$account" "$HOME/Library/Keychains/login.keychain-db" >/dev/null
```

For direct writes, use the prompt form. `security` treats `-p` and `-w password`
as insecure because they expose the secret as an argument; bare `-w` as the last
option prompts for the secret:

```bash
security add-generic-password -U -s "$service" -a "$account" "$HOME/Library/Keychains/login.keychain-db" -w
```

Do not put literal secret values in commands, transcripts, or shell history.
Disable xtrace before handling secrets and unset secret variables after use. If
non-interactive writes are required, prefer an app-specific wrapper or private
local tooling that avoids exposing the secret in process arguments.

Do not use `find-generic-password -w` for agent verification because it prints
the secret. Verify item presence only.

## Default Keychain Repair

If `security default-keychain` points at a directory or bad path, ask before
mutating. With approval:

```bash
security default-keychain -s "$HOME/Library/Keychains/login.keychain-db"
```

## Secret Handling

Never print secrets. Prefer existing authenticated tools, private files,
app-specific wrappers, or prompt-form writes. Avoid shell history exposure.
Verification should prove presence, not value.

## Failure Handling

If macOS shows "Keychain Not Found", inspect `security default-keychain`. If
prompts repeat or the user cancels, stop. Distinguish missing item from
Keychain failure.
