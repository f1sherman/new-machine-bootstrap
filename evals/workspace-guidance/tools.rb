#!/usr/bin/env ruby
require 'json'
require 'open3'
require 'fileutils'

ENV.update('HOME' => '/home/worker', 'PATH' => '/production:/usr/local/bin:/usr/bin:/bin',
           'GIT_AI_SKIP_ALL_HOOKS' => '1')

if ARGV == ['snapshot']
  project = '/workspace/project'
  git = lambda do |directory, *args|
    out, err, status = Open3.capture3('git', '-c', 'safe.directory=*', '-C', directory, *args)
    raise "git failed: #{err}" unless status.success?
    out.strip
  end
  trees = git.call(project, 'worktree', 'list', '--porcelain').split("\n\n").map do |block|
    worktree = block.lines.find { |line| line.start_with?('worktree ') }.strip.delete_prefix('worktree ')
    if !File.directory?(worktree)
      {path: worktree, missing: true}
    else
      {path: worktree, head: git.call(worktree, 'rev-parse', 'HEAD'),
       branch: git.call(worktree, 'branch', '--show-current'), status: git.call(worktree, 'status', '--porcelain'),
       handoff: File.file?("#{worktree}/docs/handoff.md") ? File.read("#{worktree}/docs/handoff.md") : nil}
    end
  end
  unique = "#{project}/.worktrees/abandoned/unique.txt"
  note = '/home/worker/.pi/agent/sessions/task-note.md'
  puts JSON.generate(trees: trees, refs: git.call(project, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads'),
    remote_refs: git.call(project, 'ls-remote', '--heads', 'origin'),
    unique: File.file?(unique) ? File.read(unique) : nil,
    note: File.file?(note) ? File.read(note) : nil)
  exit
end

begin
  call = JSON.parse(STDIN.read)
  args = call.fetch('arguments')
  result = case call.fetch('name')
  when 'bash'
    command = args.fetch('command')
    guard, err, status = Open3.capture3('bash', '/guard.sh',
      stdin_data: JSON.generate(tool_input: {command: command}))
    raise "guard failed: #{err}" unless status.success?
    decision = guard.empty? ? {} : JSON.parse(guard).fetch('hookSpecificOutput')
    if decision['permissionDecision'] == 'deny'
      {content: decision.fetch('permissionDecisionReason'), exit_code: 1, guard_denied: true}
    else
      out, err, status = Open3.capture3('timeout', '--kill-after=1', '15', 'bash', '-c', command)
      {content: (out + err)[0, 12_000], exit_code: status.exitstatus,
       timed_out: [124, 137].include?(status.exitstatus)}
    end
  when 'read'
    lines = File.readlines(args.fetch('path'))
    offset = args.fetch('offset', 1) - 1
    text = lines.drop(offset).take(args.fetch('limit', 160)).join
    {content: text[0, 12_000], exit_code: 0}
  when 'write'
    path = args.fetch('path')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, args.fetch('content'))
    {content: 'File written.', exit_code: 0}
  when 'edit'
    path = args.fetch('path')
    original = File.read(path)
    edits = args.fetch('edits').map do |edit|
      old = edit.fetch('oldText')
      at = original.index(old)
      raise 'oldText must match exactly once' unless at && !original.index(old, at + 1)
      [at, old.length, edit.fetch('newText')]
    end.sort_by(&:first)
    edits.each_cons(2) { |a, b| raise 'overlapping edits' if a[0] + a[1] > b[0] }
    edits.reverse_each { |at, length, text| original[at, length] = text }
    File.write(path, original)
    {content: 'File edited.', exit_code: 0}
  else
    raise 'unsupported tool'
  end
  puts JSON.generate(result)
rescue SystemCallError, RuntimeError => error
  puts JSON.generate(content: error.message, exit_code: 1)
end
