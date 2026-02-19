# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'

module ClaudeSessionSyncer
  CLAUDE_PROJECTS_DIR = File.expand_path('~/.claude/projects')
  DEFAULT_DAYS = 7

  class << self
    # Find local project directory for a repository name
    # Searches ~/.claude/projects/ for directories ending with the repo name
    def find_local_project_dir(repo_name)
      return nil unless Dir.exist?(CLAUDE_PROJECTS_DIR)

      Dir.children(CLAUDE_PROJECTS_DIR).find do |dir|
        dir.end_with?("-#{repo_name}")
      end&.then { |dir| File.join(CLAUDE_PROJECTS_DIR, dir) }
    end

    # Get the remote project directory path for a Codespace
    # Uses ~ which will be expanded on the remote system
    def remote_project_dir(repo_name)
      "~/.claude/projects/-workspaces-#{repo_name}"
    end

    # Find session files modified within the last N days
    def find_recent_sessions(project_dir, days: DEFAULT_DAYS)
      return [] unless project_dir && Dir.exist?(project_dir)

      cutoff = Time.now - (days * 24 * 60 * 60)

      Dir.glob(File.join(project_dir, '*.jsonl')).select do |file|
        File.mtime(file) > cutoff
      end
    end

    # Get last message timestamp from a session file
    # Returns nil if file doesn't exist or has no valid timestamp
    # Timestamp may be at top level or nested in 'snapshot' object
    def get_last_timestamp(file_path)
      return nil unless File.exist?(file_path)

      last_line = `tail -1 '#{file_path}' 2>/dev/null`.strip
      return nil if last_line.empty?

      data = JSON.parse(last_line)
      extract_timestamp(data)
    rescue JSON::ParserError, StandardError
      nil
    end

    # Get last message timestamp from remote session file
    def get_remote_last_timestamp(codespace_name, remote_path)
      stdout, _stderr, status = Open3.capture3(
        "gh codespace ssh -c #{codespace_name} -- 'tail -1 \"#{remote_path}\" 2>/dev/null'"
      )
      return nil unless status.success?

      last_line = stdout.strip
      return nil if last_line.empty?

      data = JSON.parse(last_line)
      extract_timestamp(data)
    rescue JSON::ParserError, StandardError
      nil
    end

    # Compare timestamps, returns true if ts1 is newer than ts2
    # nil timestamps are treated as oldest (missing file)
    def timestamp_newer?(ts1, ts2)
      return true if ts2.nil? && ts1
      return false if ts1.nil?

      ts1 > ts2
    end

    # Sync a single session file to Codespace (newer timestamp wins)
    def sync_session_to_codespace(local_session, codespace_name, remote_project_dir)
      session_id = File.basename(local_session, '.jsonl')
      remote_session = File.join(remote_project_dir, "#{session_id}.jsonl")

      local_ts = get_last_timestamp(local_session)
      remote_ts = get_remote_last_timestamp(codespace_name, remote_session)

      if timestamp_newer?(local_ts, remote_ts)
        # Local is newer (or remote doesn't exist) - push local
        ensure_remote_dir(codespace_name, remote_project_dir)
        transfer_to_codespace(local_session, codespace_name, remote_session)

        # Also sync associated directory if it exists
        local_dir = local_session.sub(/\.jsonl$/, '')
        if Dir.exist?(local_dir)
          remote_dir = remote_session.sub(/\.jsonl$/, '')
          sync_directory_to_codespace(local_dir, codespace_name, remote_dir)
        end

        :pushed
      else
        :skipped
      end
    end

    # Sync a single session file from Codespace (newer timestamp wins)
    def sync_session_from_codespace(remote_session, codespace_name, local_project_dir)
      session_id = File.basename(remote_session, '.jsonl')
      local_session = File.join(local_project_dir, "#{session_id}.jsonl")

      remote_ts = get_remote_last_timestamp(codespace_name, remote_session)
      local_ts = get_last_timestamp(local_session)

      if timestamp_newer?(remote_ts, local_ts)
        # Remote is newer (or local doesn't exist) - pull remote
        FileUtils.mkdir_p(local_project_dir)
        transfer_from_codespace(remote_session, codespace_name, local_session)

        # Also sync associated directory if it exists
        remote_dir = remote_session.sub(/\.jsonl$/, '')
        if remote_dir_exists?(codespace_name, remote_dir)
          local_dir = local_session.sub(/\.jsonl$/, '')
          sync_directory_from_codespace(remote_dir, codespace_name, local_dir)
        end

        :pulled
      else
        :skipped
      end
    end

    # High-level: sync all recent sessions to Codespace
    def sync_sessions_to_codespace(repo_name, codespace_name, days: DEFAULT_DAYS)
      local_dir = find_local_project_dir(repo_name)
      unless local_dir
        puts "    No local Claude sessions found for #{repo_name}"
        return { pushed: 0, skipped: 0 }
      end

      remote_dir = remote_project_dir(repo_name)
      sessions = find_recent_sessions(local_dir, days: days)

      if sessions.empty?
        puts "    No recent sessions to sync (last #{days} days)"
        return { pushed: 0, skipped: 0 }
      end

      puts "    Found #{sessions.length} session(s) from last #{days} days"

      results = { pushed: 0, skipped: 0 }
      sessions.each do |session|
        result = sync_session_to_codespace(session, codespace_name, remote_dir)
        results[result] += 1
      end

      puts "    Pushed: #{results[:pushed]}, Skipped: #{results[:skipped]}"
      results
    end

    # High-level: sync all recent sessions from Codespace
    def sync_sessions_from_codespace(repo_name, codespace_name, days: DEFAULT_DAYS)
      local_dir = find_local_project_dir(repo_name)
      remote_dir = remote_project_dir(repo_name)

      # List remote sessions
      sessions = find_remote_recent_sessions(codespace_name, remote_dir, days: days)

      if sessions.empty?
        puts "    No recent sessions in Codespace (last #{days} days)"
        return { pulled: 0, skipped: 0 }
      end

      puts "    Found #{sessions.length} session(s) in Codespace"

      # Ensure local project dir exists (may be first sync)
      using_fallback = local_dir.nil?
      target_dir = local_dir || File.join(CLAUDE_PROJECTS_DIR, "-workspaces-#{repo_name}")
      FileUtils.mkdir_p(target_dir)

      if using_fallback
        puts "    Warning: No local Claude session directory found for #{repo_name}"
        puts "             Sessions will be stored in: #{target_dir}"
        puts "             Run Claude Code locally first to create the proper session directory"
      end

      results = { pulled: 0, skipped: 0 }
      sessions.each do |session|
        result = sync_session_from_codespace(session, codespace_name, target_dir)
        results[result] += 1
      end

      puts "    Pulled: #{results[:pulled]}, Skipped: #{results[:skipped]}"
      results
    end

    private

    # Extract timestamp from session record (may be at top level or in snapshot)
    def extract_timestamp(data)
      data['timestamp'] || data.dig('snapshot', 'timestamp')
    end

    def ensure_remote_dir(codespace_name, remote_dir)
      system("gh codespace ssh -c #{codespace_name} -- 'mkdir -p \"#{remote_dir}\"' 2>/dev/null")
    end

    def remote_dir_exists?(codespace_name, remote_dir)
      system("gh codespace ssh -c #{codespace_name} -- 'test -d \"#{remote_dir}\"' 2>/dev/null")
    end

    def transfer_to_codespace(local_file, codespace_name, remote_file)
      local_dir = File.dirname(local_file)
      local_name = File.basename(local_file)
      remote_dir = File.dirname(remote_file)
      # Use cd && tar approach which handles quoting better with gh codespace ssh
      cmd = "tar -cf - --no-xattrs -C '#{local_dir}' '#{local_name}' | " \
            "gh codespace ssh -c #{codespace_name} -- \"cd '#{remote_dir}' && tar -xf -\""
      system(cmd)
    end

    def transfer_from_codespace(remote_file, codespace_name, local_file)
      FileUtils.mkdir_p(File.dirname(local_file))
      remote_dir = File.dirname(remote_file)
      remote_name = File.basename(remote_file)
      local_dir = File.dirname(local_file)
      cmd = "gh codespace ssh -c #{codespace_name} -- \"cd '#{remote_dir}' && tar -cf - '#{remote_name}'\" | " \
            "tar -xf - -C '#{local_dir}'"
      system(cmd)
    end

    def sync_directory_to_codespace(local_dir, codespace_name, remote_dir)
      ensure_remote_dir(codespace_name, File.dirname(remote_dir))
      parent_dir = File.dirname(local_dir)
      dir_name = File.basename(local_dir)
      remote_parent = File.dirname(remote_dir)
      cmd = "tar -cf - --no-xattrs -C '#{parent_dir}' '#{dir_name}' | " \
            "gh codespace ssh -c #{codespace_name} -- \"cd '#{remote_parent}' && tar -xf -\""
      system(cmd)
    end

    def sync_directory_from_codespace(remote_dir, codespace_name, local_dir)
      FileUtils.mkdir_p(File.dirname(local_dir))
      remote_parent = File.dirname(remote_dir)
      dir_name = File.basename(remote_dir)
      local_parent = File.dirname(local_dir)
      cmd = "gh codespace ssh -c #{codespace_name} -- \"cd '#{remote_parent}' && tar -cf - '#{dir_name}'\" | " \
            "tar -xf - -C '#{local_parent}'"
      system(cmd)
    end

    def find_remote_recent_sessions(codespace_name, remote_dir, days: DEFAULT_DAYS)
      # Find .jsonl files modified in last N days
      cmd = "gh codespace ssh -c #{codespace_name} -- " \
            "'find \"#{remote_dir}\" -maxdepth 1 -name \"*.jsonl\" -mtime -#{days} 2>/dev/null'"
      stdout, _stderr, status = Open3.capture3(cmd)
      return [] unless status.success?

      stdout.strip.split("\n").reject(&:empty?)
    end
  end
end
