#!/bin/bash
set -eu
chown -R root:root /workspace
find /workspace -type d -exec chmod 755 {} +
find /workspace -type f -exec chmod 644 {} +
chmod 1777 /workspace
chown worker:worker /workspace/active.json
