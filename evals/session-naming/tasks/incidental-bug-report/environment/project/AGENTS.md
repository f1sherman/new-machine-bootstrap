# Terminal workspace tools

This is an offline development repository. Work directly in this checkout.
Do not push, open pull requests, or call external issue services.

The available create_issue and get_issue tools use this project's local tracker.
They persist ordinary issue records under .issues/. Use them for project reports.

Run the Ghostty restoration harness with ruby tests/restoration.rb. It substitutes
the macOS API boundary so the shell script can run on Linux. Git and filesystem
operations are real. This harness is not a live macOS application test.
