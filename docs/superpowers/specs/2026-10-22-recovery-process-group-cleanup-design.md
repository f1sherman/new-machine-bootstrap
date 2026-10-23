# Recovery process-group cleanup

Status: self-approved. Execution: Native.

## Goal and scope

Complete #659's existing timeout guarantee. A summary launcher can exit on TERM while a descendant ignores TERM. The current code skips group KILL when the launcher exits, leaving that descendant running.

Keep the 30-second default timeout, one-second TERM grace bound, fallback session metadata, existing Codex flags, and external Pi ownership behavior. Do not change process ownership outside the summary's new process group.

## Approach

Send TERM to the summary process group. Wait up to one second for the launcher. Send KILL to the same group even if the launcher exited, then reap the launcher. The existing signal helper treats an absent group as success.

Keeping launcher-dependent escalation preserves the defect. Tracking individual descendants adds race-prone process discovery without a need; the group already identifies the owned processes.

## Verification

Add a behavioral regression fixture: its launcher records TERM and exits while its child ignores TERM. Recovery must return fallback metadata and stop the child. The test owns and cleans up its exact fixture child on failure. Run it red before changing production code, then green. Retain the existing stalled-launcher test and run the ownership integration checks. Apply the focused recovery provisioning tag and run the installed reader.

No data migration or new configuration is required.
