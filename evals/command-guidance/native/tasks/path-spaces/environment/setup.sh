#!/bin/bash
set -euo pipefail
f='/home/eval/Library/Application Support/Remote Environment/production'
mkdir -p "$f"
printf 'example: true\n' > "$f/service settings.yaml"
