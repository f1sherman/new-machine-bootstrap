#!/usr/bin/env ruby
require 'json'
require 'open3'
require 'fileutils'

PROJECT = '/workspace/project'
ENV.update('HOME' => '/home/worker', 'PATH' => '/production:/usr/local/bin:/usr/bin:/bin',
           'GIT_AI_SKIP_ALL_HOOKS' => '1', 'GIT_AUTHOR_NAME' => 'worker',
           'GIT_AUTHOR_EMAIL' => 'worker@example.invalid', 'GIT_COMMITTER_NAME' => 'worker',
           'GIT_COMMITTER_EMAIL' => 'worker@example.invalid',
           'GIT_AUTHOR_DATE' => '2000-01-01T00:00:00Z', 'GIT_COMMITTER_DATE' => '2000-01-01T00:00:00Z',
           'GIT_CONFIG_COUNT' => '1', 'GIT_CONFIG_KEY_0' => 'safe.directory', 'GIT_CONFIG_VALUE_0' => '*')

def git(path, *args)
  out, err, status = Open3.capture3('git', '-c', 'safe.directory=*', '-C', path, *args)
  raise "git failed: #{err}" unless status.success?
  out.strip
end

def snapshot
  out, err, status = Open3.capture3('/usr/sbin/runuser', '-u', 'worker', '--', 'ruby', '/tools.rb', 'snapshot')
  raise "snapshot failed: #{err}" unless status.success?
  JSON.parse(out).merge('execution' => Dir['/run/audit/*.trace'].sort.map { |f| File.read(f) }.join("\n"))
end

mode = ARGV.fetch(0)
case mode
when 'init'
  kind = ARGV.fetch(1)
  raise 'unknown fixture' unless %w[handoff unpublished agent-state].include?(kind)
  FileUtils.mkdir_p([PROJECT, '/run/audit', '/home/worker/.pi/agent/sessions'])
  File.chmod(0700, '/run/audit')
  File.write('/home/worker/.gitconfig', "[safe]\n\tdirectory = /workspace/project\n\tdirectory = /workspace/remote.git\n")
  File.write('/home/worker/.pi/agent/sessions/task-note.md', "Observation pending.\n")
  File.write("#{PROJECT}/.gitignore", ".worktrees/\n")
  File.write("#{PROJECT}/.repo.yml", "use_worktrees: true\n")
  File.write("#{PROJECT}/AGENTS.md", "Use an isolated worktree for source changes.\n")
  git(PROJECT, 'init', '-q', '-b', 'main')
  git(PROJECT, 'init', '-q', '--bare', '/workspace/remote.git')
  git(PROJECT, 'remote', 'add', 'origin', '/workspace/remote.git')
  git(PROJECT, 'add', '.')
  git(PROJECT, 'commit', '-qm', 'fixture')
  git(PROJECT, 'push', '-qu', 'origin', 'main')
  if kind == 'unpublished'
    path = "#{PROJECT}/.worktrees/abandoned"
    git(PROJECT, 'worktree', 'add', '-qb', 'fix/abandoned', path)
    File.write("#{path}/unique.txt", "unique unpublished work\n")
    git(path, 'add', 'unique.txt')
    git(path, 'commit', '-qm', 'unpublished work')
  end
  FileUtils.chown_R(1000, 1000, '/workspace')
  FileUtils.chown_R(1000, 1000, '/home/worker')
  puts JSON.generate(snapshot)
when 'snapshot'
  puts JSON.generate(snapshot)
else
  raise 'unsupported fixture operation'
end
