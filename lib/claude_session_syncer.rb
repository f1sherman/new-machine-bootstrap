# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require_relative 'remote_transport'

module ClaudeSessionSyncer
  CLAUDE_PROJECTS_DIR = File.expand_path('~/.claude/projects')
  DEFAULT_DAYS = 7

  class << self
    def find_local_project_dir(repo_name)
      return nil unless Dir.exist?(CLAUDE_PROJECTS_DIR)

      Dir.children(CLAUDE_PROJECTS_DIR).find do |dir|
        dir.end_with?("-#{repo_name}")
      end&.then { |dir| File.join(CLAUDE_PROJECTS_DIR, dir) }
    end

    # Uses $HOME (not ~) because ~ doesn't expand inside quotes
    def remote_project_dir(repo_name)
      "$HOME/.claude/projects/-workspaces-#{repo_name}"
    end

    def find_recent_sessions(project_dir, days: DEFAULT_DAYS)
      return [] unless project_dir && Dir.exist?(project_dir)

      cutoff = Time.now - (days * 24 * 60 * 60)

      Dir.glob(File.join(project_dir, '*.jsonl')).select do |file|
        File.mtime(file) > cutoff
      end
    end

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

    # nil timestamps are treated as oldest (missing file)
    def timestamp_newer?(ts1, ts2)
      return true if ts2.nil? && ts1
      return false if ts1.nil?

      ts1 > ts2
    end

    # High-level: sync all recent sessions to remote workspace (batched: 1-2 SSH calls)
    def sync_sessions_to_codespace(repo_name, codespace_name, days: DEFAULT_DAYS, transport: nil)
      transport ||= RemoteTransport::CodespaceTransport.new(codespace_name)

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

      remote_metadata = fetch_remote_metadata(remote_dir, days, transport: transport)

      items_to_push = []
      pushed_count = 0
      skipped_count = 0

      sessions.each do |session_path|
        filename = File.basename(session_path)
        session_id = File.basename(filename, '.jsonl')
        local_ts = get_last_timestamp(session_path)
        remote_ts = remote_metadata.dig(filename, :timestamp)

        if timestamp_newer?(local_ts, remote_ts)
          items_to_push << filename
          local_assoc_dir = session_path.sub(/\.jsonl$/, '')
          items_to_push << session_id if Dir.exist?(local_assoc_dir)
          pushed_count += 1
        else
          skipped_count += 1
        end
      end

      batch_transfer_to_remote(items_to_push, local_dir, remote_dir, transport: transport)

      results = { pushed: pushed_count, skipped: skipped_count }
      puts "    Pushed: #{results[:pushed]}, Skipped: #{results[:skipped]}"
      results
    end

    # High-level: sync all recent sessions from remote workspace (batched: 1-2 SSH calls)
    def sync_sessions_from_codespace(repo_name, codespace_name, days: DEFAULT_DAYS, transport: nil)
      transport ||= RemoteTransport::CodespaceTransport.new(codespace_name)
      label = transport.workspace_type

      local_dir = find_local_project_dir(repo_name)
      remote_dir = remote_project_dir(repo_name)

      remote_metadata = fetch_remote_metadata(remote_dir, days, transport: transport)

      if remote_metadata.empty?
        puts "    No recent sessions in #{label} (last #{days} days)"
        return { pulled: 0, skipped: 0 }
      end

      puts "    Found #{remote_metadata.length} session(s) in #{label}"

      using_fallback = local_dir.nil?
      target_dir = local_dir || File.join(CLAUDE_PROJECTS_DIR, "-workspaces-#{repo_name}")
      FileUtils.mkdir_p(target_dir)

      if using_fallback
        puts "    Warning: No local Claude session directory found for #{repo_name}"
        puts "             Sessions will be stored in: #{target_dir}"
        puts "             Run Claude Code locally first to create the proper session directory"
      end

      items_to_pull = []
      pulled_count = 0
      skipped_count = 0

      remote_metadata.each do |filename, meta|
        local_session = File.join(target_dir, filename)
        local_ts = get_last_timestamp(local_session)

        if timestamp_newer?(meta[:timestamp], local_ts)
          items_to_pull << filename
          session_id = File.basename(filename, '.jsonl')
          items_to_pull << session_id if meta[:has_dir]
          pulled_count += 1
        else
          skipped_count += 1
        end
      end

      batch_transfer_from_remote(items_to_pull, remote_dir, target_dir, transport: transport)

      results = { pulled: pulled_count, skipped: skipped_count }
      puts "    Pulled: #{results[:pulled]}, Skipped: #{results[:skipped]}"
      results
    end

    private

    def extract_timestamp(data)
      data['timestamp'] || data.dig('snapshot', 'timestamp')
    end

    # Returns: { "session.jsonl" => { timestamp: String|nil, has_dir: Boolean } }
    def fetch_remote_metadata(remote_dir, days, transport:)
      script = [
        'dir="#{dir}"; days=#{days};',
        '[ -d "$dir" ] || exit 0;',
        'find "$dir" -maxdepth 1 -name "*.jsonl" -mtime -"$days" -print0 |',
        'while IFS= read -r -d "" f; do',
        '  name="$(basename "$f")";',
        '  last=$(tail -1 "$f" 2>/dev/null);',
        '  ts="";',
        '  if [ -n "$last" ]; then',
        '    ts=$(printf "%s" "$last" | grep -o "\"timestamp\":\"[^\"]*\"" | head -1 | cut -d"\"" -f4);',
        '  fi;',
        '  has_dir="false";',
        '  [ -d "${f%.jsonl}" ] && has_dir="true";',
        '  printf "%s\t%s\t%s\n" "$name" "$ts" "$has_dir";',
        'done'
      ].join(' ')

      script = script.gsub('#{dir}', remote_dir).gsub('#{days}', days.to_s)

      stdout, _stderr, status = Open3.capture3(
        "#{transport.ssh_prefix} '#{script}'"
      )
      return {} unless status.success?

      metadata = {}
      stdout.strip.split("\n").each do |line|
        next if line.empty?

        parts = line.split("\t", 3)
        next unless parts.length == 3

        name, ts, has_dir = parts
        metadata[name] = {
          timestamp: ts.empty? ? nil : ts,
          has_dir: has_dir == 'true'
        }
      end
      metadata
    end

    def batch_transfer_to_remote(items, local_dir, remote_dir, transport:)
      return if items.empty?

      item_args = items.map { |i| "'#{i}'" }.join(' ')
      cmd = "tar -cf - --no-xattrs -C '#{local_dir}' #{item_args} | " \
            "#{transport.ssh_prefix} " \
            "'mkdir -p \"#{remote_dir}\" && tar -xf - -C \"#{remote_dir}\"'"
      system(cmd)
    end

    def batch_transfer_from_remote(items, remote_dir, local_dir, transport:)
      return if items.empty?

      FileUtils.mkdir_p(local_dir)
      item_args = items.map { |i| "\"#{i}\"" }.join(' ')
      cmd = "#{transport.ssh_prefix} " \
            "'tar -cf - -C \"#{remote_dir}\" #{item_args}' | " \
            "tar -xf - -C '#{local_dir}'"
      system(cmd)
    end
  end
end
