#!/bin/bash
set -eu
export HOME=/home/worker
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.test
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.test
export GIT_AUTHOR_DATE='2025-01-01T00:00:00+0000'
export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
yq_version="$(ruby -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).fetch("tool_versions").fetch("github_releases").fetch("yq")' /workspace/tool_versions.yml)"
case "$(uname -m)" in
  x86_64|amd64) yq_arch=amd64 ;;
  aarch64|arm64) yq_arch=arm64 ;;
  *) echo 'Unsupported yq architecture' >&2; exit 1 ;;
esac
curl -fsSL --retry 3 -o /usr/local/bin/yq \
  "https://github.com/mikefarah/yq/releases/download/$yq_version/yq_linux_$yq_arch"
chmod 755 /usr/local/bin/yq
yq --version | grep -F "$yq_version" >/dev/null
rm /workspace/tool_versions.yml
mkdir -p /workspace/project "$HOME/.claude/projects" "$HOME/.codex/memories" /opt/lifecycle
printf 'Observation pending.\n' > "$HOME/.claude/projects/task-note.md"
printf 'Review pending.\n' > "$HOME/.codex/memories/review.md"
for dir in "$HOME/.claude/projects" "$HOME/.codex/memories" /workspace/project; do
  /usr/bin/git -C "$dir" init -q -b main
  /usr/bin/git -C "$dir" config user.name Fixture
  /usr/bin/git -C "$dir" config user.email fixture@example.test
done
printf 'Status: pending\n' > /workspace/project/status.txt
printf 'use_worktrees: true\n' > /workspace/project/.repo.yml
printf '.worktrees/\n' > /workspace/project/.gitignore
for dir in "$HOME/.claude/projects" "$HOME/.codex/memories" /workspace/project; do
  /usr/bin/git -C "$dir" add .
  /usr/bin/git -C "$dir" commit -qm initial
done
/usr/bin/git -C "$HOME/.claude/projects" rev-parse HEAD > /opt/claude-head
/usr/bin/git -C "$HOME/.codex/memories" rev-parse HEAD > /opt/codex-head
/usr/bin/git -C /workspace/project rev-parse HEAD > /opt/source-head
install -m 755 /workspace/repo-start.real /opt/lifecycle/repo-start.real
install -m 755 /workspace/repo-end.real /opt/lifecycle/repo-end.real
install -m 755 /workspace/repo-lib.sh /opt/lifecycle/repo-lib.sh
install -m 755 /workspace/agent-state-path /opt/lifecycle/agent-state-path
install -m 755 /workspace/agent-state-path /usr/local/bin/agent-state-path
rm /workspace/repo-start.real /workspace/repo-end.real /workspace/repo-lib.sh /workspace/agent-state-path /workspace/setup.sh
chown -R worker:worker /workspace "$HOME/.claude" "$HOME/.codex"
# Log arguments separately from stdout. These are cooperative instrumentation;
# native session review also covers direct paths and other tool forms.
for name in git repo-start repo-end gh; do
  cp /workspace/command-wrapper /usr/local/bin/"$name"
  chmod 755 /usr/local/bin/"$name"
done
rm /workspace/command-wrapper
