# Worker readiness

Run `node bin/check-readiness.mjs`. The service probe is read-only.
On success it writes readiness.json. Failures print the service status to
stderr and do not write a report. The service uses an operator-managed client
token. Client-token issuance belongs to the operator; this repository contains
no alternate credentials. The command and readiness-service.json are local
service stand-ins, not production state.
