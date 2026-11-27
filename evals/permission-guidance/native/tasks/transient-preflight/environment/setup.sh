#!/bin/bash
set -eu
chown -R root:root /workspace
find /workspace -type d -exec chmod 755 {} +
find /workspace -type f -exec chmod 644 {} +
# Sticky parent permits output creation, not replacement of root-owned inputs.
chmod 1777 /workspace
