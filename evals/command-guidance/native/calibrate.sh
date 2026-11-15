#!/bin/bash
# Build/setup is networked; grading itself is a disposable networkless container.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"
output="${1:?Supply a fresh ignored tmp/ output directory}"
[[ "$output" == tmp/* && ! -e "$output" ]]
python3 - "$output" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1]).resolve()
assert path.is_relative_to(Path.cwd() / 'tmp'), 'Keep calibration inside this checkout'
PY
mkdir -p "$output/context"
version=$(ruby -ryaml -e 'puts YAML.safe_load(File.read("vars/tool_versions.yml")).fetch("tool_versions").fetch("runtimes").fetch("pi_coding_agent")')
owner="terminal-calibration-$(date +%s)-$$"
docker build --build-arg "PI_VERSION=$version" -t "$owner-runtime" \
  -f evals/runner/Dockerfile evals/runner >"$output/runtime-build.log" 2>&1
cp evals/command-guidance/native/{verify.py,calibrate.py,capture.py} "$output/context/"
cp -R evals/command-guidance/native/tasks "$output/context/cases"
cat >"$output/context/Dockerfile" <<DOCKER
FROM $owner-runtime
RUN apt-get update && apt-get install -y --no-install-recommends zsh \\
    && rm -rf /var/lib/apt/lists/*
COPY verify.py calibrate.py /tests/
COPY cases /opt/cases
COPY capture.py /opt/command-stubs/capture.py
RUN chmod 755 /opt/command-stubs/capture.py \\
    && for name in cat curl tool; do ln -s capture.py /opt/command-stubs/\$name; done \\
    && mkdir -p /logs/verifier
DOCKER
docker build -t "$owner" "$output/context" >"$output/grader-build.log" 2>&1
docker image inspect "$owner" --format '{{.Id}}' >"$output/image-id.txt"
docker run --rm --network none --pids-limit 128 "$owner" \
  python3 /tests/calibrate.py | tee "$output/results.json"
