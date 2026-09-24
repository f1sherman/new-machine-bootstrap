# ChatGPT Fastmail Personal Safari Routing Design

Status: Self-approved

## Goal

Links to `fastmail.com` or a subdomain, when clicked in ChatGPT, open in the existing Safari Personal profile window. Other ChatGPT links keep their Chrome behavior.

## Assumptions and boundaries

- ChatGPT is the exact sender bundle `com.openai.codex`.
- Only `fastmail.com` and its subdomains are in scope. Other Fastmail-owned domains are not assumed to match.
- Match the parsed, case-insensitive host at a label boundary, not URL text. Reject deceptive suffixes and hosts that contain Fastmail only in a path or userinfo.
- Use the existing Personal Safari resolver and the dedicated Safari route shared with Todoist and Slack. An absent or ambiguous Personal window uses normal Safari once. Never retry after tab creation.
- Do not move, summon, resize, or close windows. Do not change other senders' routes. Do not provision or reload Hammerspoon without explicit approval.

## Recommended design

Add a pure URL-destination classifier to `omniwm_url_source.lua`. For the exact ChatGPT sender it uses `hs.http.urlParts` to read the URL host and returns Personal Safari only for the accepted host boundary; otherwise it selects Chrome. Malformed URLs or parser failures remain on the existing Chrome path. The HTTP callback uses that classifier before its normal ChatGPT Chrome dispatch and calls the existing profile-Safari helper with a Fastmail-specific error message. Split Safari tab creation from tab selection so selection failures report an error but cannot trigger a second open. This applies to the shared Slack and Todoist profile route as well. After confirmed creation, navigate to the exact window without fallback.

Alternatives: A substring search is smaller but mistakes a URL path, userinfo, or deceptive hostname for Fastmail. A new Safari routing module duplicates the established profile flow with no added value. The existing helper plus a parsed-host classifier is safer and smaller.

## Verification and rollout

Exercise the production classifier with representative parsed URL fixtures: apex, subdomain, mixed case, non-Fastmail, deceptive host, and malformed input. Exercise the existing Safari router for absent target, creation failure, and post-creation navigation failure. Run the OmniWM Lua suite, syntax checks, Ruby settings tests, Ansible syntax, and diff checks. Update the OmniWM cheat sheet. Create a PR; deployment and any live URL test require separate approval.
