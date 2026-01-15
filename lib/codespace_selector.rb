# frozen_string_literal: true

require 'json'
require 'open3'
require 'shellwords'

module CodespaceSelector
  class SelectionError < StandardError; end

  class << self
    def select_codespace(codespace_name: nil, filter_available: false)
      ensure_gh_installed

      return codespace_name if codespace_name

      codespaces = fetch_codespaces
      codespaces = codespaces.select { |cs| cs['state'] == 'Available' } if filter_available

      if codespaces.empty?
        raise SelectionError, filter_available ?
          "No available Codespaces found. Create one with: codespace-create" :
          "No Codespaces found. Create one with: codespace-create"
      end

      return codespaces[0]['name'] if codespaces.size == 1

      ensure_fzf_installed
      select_with_fzf(codespaces)
    end

    def all_available_codespaces
      ensure_gh_installed
      fetch_codespaces.select { |cs| cs['state'] == 'Available' }.map { |cs| cs['name'] }
    end

    private

    def command_exists?(cmd)
      system("command -v #{cmd} >/dev/null 2>&1")
    end

    def in_tmux?
      ENV['TMUX'] && !ENV['TMUX'].empty?
    end

    def ensure_gh_installed
      return if command_exists?('gh')

      raise SelectionError, "gh CLI is required but not installed. Install it with: brew install gh"
    end

    def ensure_fzf_installed
      return if command_exists?('fzf')

      raise SelectionError, "Multiple Codespaces found, but fzf is not installed. Install it with: brew install fzf"
    end

    def fetch_codespaces
      stdout, stderr, status = Open3.capture3('gh codespace list --json name,repository,state,gitStatus')

      unless status.success?
        raise SelectionError, "Failed to list Codespaces: #{stderr}"
      end

      JSON.parse(stdout)
    end

    def select_with_fzf(codespaces)
      selected = if in_tmux?
                   select_with_fzf_popup(codespaces)
                 else
                   select_with_fzf_inline(codespaces)
                 end

      raise SelectionError, "No Codespace selected" unless selected

      selected
    end

    def truncate(str, max_length)
      return str if str.length <= max_length

      str[0, max_length - 3] + '...'
    end

    def build_fzf_input(codespaces, terminal_width)
      available_width = terminal_width - 18
      name_width = [(available_width * 0.35).to_i, 15].max
      branch_width = [(available_width * 0.65).to_i, 20].max

      header = format("%-#{name_width}s  %-#{branch_width}s  %s", 'NAME', 'BRANCH', 'STATE')

      lines = codespaces.map do |cs|
        full_name = cs['name']
        display_name = truncate(full_name, name_width)
        branch = truncate(cs.dig('gitStatus', 'ref') || 'unknown', branch_width)
        state = cs['state'] || 'unknown'

        display = format("%-#{name_width}s  %-#{branch_width}s  %s", display_name, branch, state)
        "#{display}\t#{full_name}"
      end

      [header, lines.join("\n")]
    end

    def select_with_fzf_inline(codespaces)
      terminal_width = `tput cols`.to_i rescue 80
      header, input = build_fzf_input(codespaces, terminal_width)

      stdout, _stderr, status = Open3.capture3(
        'fzf',
        '--delimiter', "\t",
        '--with-nth', '1',
        '--layout', 'reverse',
        '--header', header,
        '--prompt', 'Select Codespace: ',
        stdin_data: input
      )

      return nil unless status.success?

      stdout.strip.split("\t").last
    end

    def select_with_fzf_popup(codespaces)
      require 'tempfile'

      popup_width = 120
      header, input = build_fzf_input(codespaces, popup_width)

      input_file = Tempfile.new(['codespace-input', '.txt'])
      output_file = Tempfile.new(['codespace-output', '.txt'])
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
            --prompt='Select Codespace: ' \
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
