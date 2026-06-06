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
rg -n "Keychain|add-generic-password|find-generic-password|keychain" lib test bin
```

Use the wrapper if available.

## Direct Security Commands

Always pass the explicit keychain path as the final argument:

```bash
security add-generic-password -U -s "$service" -a "$account" -w "$secret" "$HOME/Library/Keychains/login.keychain-db"
security find-generic-password -s "$service" -a "$account" "$HOME/Library/Keychains/login.keychain-db" >/dev/null
```

Populate `$secret` from a non-logged source, such as an existing authenticated
tool, a private file, or a silent prompt. Do not put literal secret values in
commands, transcripts, or shell history. Disable xtrace before handling secrets
and unset secret variables after use.

Do not use `find-generic-password -w` for agent verification because it prints
the secret. Verify item presence only.

## Default Keychain Repair

If `security default-keychain` points at a directory or bad path, ask before
mutating. With approval:

```bash
security default-keychain -s "$HOME/Library/Keychains/login.keychain-db"
```

## Secret Handling

Never print secrets. Prefer reading from existing authenticated tools or
private files. Avoid shell history exposure. Verification should prove
presence, not value.

## Failure Handling

If macOS shows "Keychain Not Found", inspect `security default-keychain`. If
prompts repeat or the user cancels, stop. Distinguish missing item from
Keychain failure.
