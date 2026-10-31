# Existing Pi login for native permission evals

## Problem and benefit
The permission suite rejects `openai-codex` before execution and requires a separate API key. Brian already has a working Pi login. Reuse it without changing the native tools, continued session, observers, or graders.

## Scope
Support `openai-codex/model` for permission-guidance only. Keep existing API-key paths unchanged. No deployed guidance, provider credentials, Docker settings, merge settings, or persistent automation changes. Keep reserved holdouts out of development runs.

## Design
A small Harbor Pi subclass wraps each native user step. A host-only Pi auth command exports an access token with at least five minutes of validity. The wrapper checks the JWT expiry and uploads a private runtime auth.json containing only the access token, actual expiry, and an empty refresh placeholder. Native Pi requires the OAuth credential type for this subscription provider; a plain API-key entry failed a local smoke. The access-only OAuth shape passed a real inference smoke.

The driver resolves the host Pi executable and original agent directory before isolating HOME. These paths enter only the Harbor host process environment. Tokens never enter argv, agent options, manifests, or environment variables. The temporary host file is created with mode 0600. Container auth is removed after each step, including failure. Harbor container deletion is the fallback after process death. No host auth.json, refresh token, settings, extensions, or sessions are mounted or copied.

Reject custom endpoints, MCP, or agent-directory overrides that would move native Pi away from the observed fixture configuration. Validate expiry before inference and fail as infrastructure if auth acquisition, transfer, or cleanup fails. Do not retry scored model outcomes.

## Alternatives and safety
A host inference broker could keep every provider credential outside Docker, but would add provider streaming and lifecycle machinery. A host-native controller with replaced tools would change the behavior under test. The access-only wrapper keeps stock Pi's native lifecycle and is smaller.

The cooperative fixture agent runs as root and can read the short-lived bearer while it exists. File permissions do not isolate it from its own credential. This mode is not suitable for hostile tasks. Refresh credentials remain outside Docker. The two design reviewers use the same configured model; they provide separate contexts, not model diversity.

## Verification and acceptance
Reproduce provider rejection, test secret transfer and cleanup through the production adapter, then require a real continued Harbor workflow with existing Pi auth and no API key. Check task and authority outcomes, native settlement, consistent tool evidence, session continuity, usage, and absence of credential material in retained artifacts. Keep failed runs separate.

The original five-condition experiment used the API-key provider. Any later comparison must refreeze all conditions with the OAuth provider. Authentication repair evidence is not a guidance comparison.

Status: self-reviewed and approved for implementation. Both independent design contexts recommend the access-only wrapper for this cooperative-fixture boundary. The alternative review was recovered through its registered child after the workflow timeout. No fallback launcher was used.
