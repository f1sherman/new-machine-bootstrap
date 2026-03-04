# frozen_string_literal: true

require 'json'
require 'open3'
require 'shellwords'

module DevpodSelector
  class SelectionError < StandardError; end

  class << self
    def select_workspace(workspace_name: nil)
      ensure_devpod_installed

      return workspace_name if workspace_name

      workspaces = fetch_workspaces

      if workspaces.empty?
        raise SelectionError, "No DevPod workspaces found. Create one with: devpod-create"
      end

      return workspaces[0]['id'] if workspaces.size == 1

      ensure_fzf_installed
      select_with_fzf(workspaces)
    end

    def all_running_workspaces
      ensure_devpod_installed
      fetch_workspaces.map { |ws| ws['id'] }
    end

    def repo_name_for_workspace(workspace_name)
      ensure_devpod_installed
      ws = fetch_workspaces.find { |w| w['id'] == workspace_name }
      return nil unless ws

      source = ws.dig('source', 'gitRepository') || ws.dig('source', 'localFolder')
      return nil unless source

      source.split('/').last.sub(/\.git$/, '')
    end

    private

    def command_exists?(cmd)
      system("command -v #{cmd} >/dev/null 2>&1")
    end

    def in_tmux?
      ENV['TMUX'] && !ENV['TMUX'].empty?
    end

    def ensure_devpod_installed
      return if command_exists?('devpod')

      raise SelectionError, "devpod CLI is required but not installed. Install from https://devpod.sh"
    end

    def ensure_fzf_installed
      return if command_exists?('fzf')

      raise SelectionError, "Multiple workspaces found, but fzf is not installed. Install it with: brew install fzf"
    end

    def fetch_workspaces
      stdout, stderr, status = Open3.capture3('devpod list --output json')

      unless status.success?
        raise SelectionError, "Failed to list DevPod workspaces: #{stderr}"
      end

      JSON.parse(stdout)
    end

    def select_with_fzf(workspaces)
      selected = if in_tmux?
                   select_with_fzf_popup(workspaces)
                 else
                   select_with_fzf_inline(workspaces)
                 end

      raise SelectionError, "No workspace selected" unless selected

      selected
    end

    def truncate(str, max_length)
      return str if str.length <= max_length

      str[0, max_length - 3] + '...'
    end

    def build_fzf_input(workspaces, terminal_width)
      available_width = terminal_width - 18
      name_width = [(available_width * 0.3).to_i, 15].max
      source_width = [(available_width * 0.5).to_i, 20].max
      provider_width = [(available_width * 0.2).to_i, 8].max

      header = format("%-#{name_width}s  %-#{source_width}s  %-#{provider_width}s", 'NAME', 'SOURCE', 'PROVIDER')

      lines = workspaces.map do |ws|
        full_name = ws['id']
        display_name = truncate(full_name, name_width)

        source = ws.dig('source', 'localFolder') || ws.dig('source', 'gitRepository') || 'unknown'
        source = truncate(source, source_width)

        provider = ws.dig('provider', 'name') || 'unknown'
        provider = truncate(provider, provider_width)

        display = format("%-#{name_width}s  %-#{source_width}s  %-#{provider_width}s", display_name, source, provider)
        "#{display}\t#{full_name}"
      end

      [header, lines.join("\n")]
    end

    def select_with_fzf_inline(workspaces)
      terminal_width = `tput cols`.to_i rescue 80
      header, input = build_fzf_input(workspaces, terminal_width)

      stdout, _stderr, status = Open3.capture3(
        'fzf',
        '--delimiter', "\t",
        '--with-nth', '1',
        '--layout', 'reverse',
        '--header', header,
        '--prompt', 'Select DevPod workspace: ',
        stdin_data: input
      )

      return nil unless status.success?

      stdout.strip.split("\t").last
    end

    def select_with_fzf_popup(workspaces)
      require 'tempfile'

      popup_width = 120
      header, input = build_fzf_input(workspaces, popup_width)

      input_file = Tempfile.new(['devpod-input', '.txt'])
      output_file = Tempfile.new(['devpod-output', '.txt'])
      input_file.write(input)
      input_file.close
      output_file.close

      input_path = input_file.path
      output_path = output_file.path

      script = <<~BASH
        fzf --delimiter=$'\\t' \
            --with-nth=1 \
            --layout=reverse \
            --header=#{Shellwords.escape(header)} \
            --prompt='Select DevPod workspace: ' \
            < #{Shellwords.escape(input_path)} \
            > #{Shellwords.escape(output_path)}
      BASH

      popup_env = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH"
      system('tmux', 'display-popup', '-E', '-w', '80%', '-h', '80%', 'bash', '-c', "#{popup_env} #{script}")

      result = File.read(output_path).strip

      File.unlink(input_path) rescue nil
      File.unlink(output_path) rescue nil

      return nil if result.empty?

      result.split("\t").last
    end
  end
end
