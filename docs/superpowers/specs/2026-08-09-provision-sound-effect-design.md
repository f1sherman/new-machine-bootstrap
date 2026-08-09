# Provision Sound Effect Design

## Goal

Replace spoken provisioning alerts with a short, nonverbal sound. This prevents provisioning from speaking aloud in shared spaces while retaining an audible completion or failure signal.

## Behavior

On macOS, `bin/provision` will play the built-in `Blow.aiff` system sound for both successful and failed provisioning runs. Linux behavior will remain silent, as it is today.

The paired Home Network Provisioning change will use the same sound for its provisioning alerts.

## Implementation

Replace the speech helper with a notification-sound helper that runs `afplay /System/Library/Sounds/Blow.aiff` only on macOS. The helper will suppress playback errors and always return success so an unavailable sound cannot change the provisioning result.

Update the success and failure call sites to use the new helper. Remove the spoken message arguments because success and failure intentionally use the same sound.

## Verification

Run Bash syntax validation for `bin/provision`. Manually play the selected system sound with `afplay` to confirm it is available and audible. Do not add an automated test because this is a low-impact preference and a source-level test would only restate static configuration.
