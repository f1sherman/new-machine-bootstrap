# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "set"
require "time"

module CodexPrReview
  class Error < StandardError; end
  class CommandError < Error; end
  class HttpError < Error; end

  class PlatformClient
    GITHUB_API_VERSION = "2022-11-28"

    def initialize(platform:, repo:, token:, pr_number:, api_base_url: nil)
      @platform = platform
      @repo = repo
      @token = token
      @pr_number = pr_number
      @api_base_url = api_base_url || default_api_base_url
    end

    def pull_request
      get_json("#{api_base_url}/repos/#{repo}/pulls/#{pr_number}")
    end

    def post_top_level_comment(body)
      post_json("#{api_base_url}/repos/#{repo}/issues/#{pr_number}/comments", { body: body })
    end

    def post_inline_comments(head_sha:, comments:)
      return if comments.empty?

      if forgejo?
        post_json(
          "#{api_base_url}/repos/#{repo}/pulls/#{pr_number}/reviews",
          {
            event: "COMMENT",
            commit_id: head_sha,
            comments: comments.map do |comment|
              {
                body: comment.fetch(:body),
                path: comment.fetch(:path),
                new_position: comment.fetch(:line)
              }
            end
          }
        )
        return
      end

      comments.each do |comment|
        post_json(
          "#{api_base_url}/repos/#{repo}/pulls/#{pr_number}/comments",
          {
            body: comment.fetch(:body),
            commit_id: head_sha,
            path: comment.fetch(:path),
            line: comment.fetch(:line),
            side: "RIGHT"
          }
        )
      end
    end

    private

    attr_reader :api_base_url, :platform, :pr_number, :repo, :token

    def default_api_base_url
      if github?
        ENV.fetch("GITHUB_API_URL", "https://api.github.com")
      else
        "#{ENV.fetch("GITHUB_SERVER_URL", "https://forgejo.brianjohn.com")}/api/v1"
      end
    end

    def default_headers
      headers = []

      if github?
        headers << "Accept: application/vnd.github+json"
        headers << "Authorization: Bearer #{token}"
        headers << "X-GitHub-Api-Version: #{GITHUB_API_VERSION}"
      else
        headers << "Authorization: token #{token}"
      end
      headers << "Content-Type: application/json"

      headers
    end

    def get_json(url)
      JSON.parse(curl!(url))
    rescue JSON::ParserError => e
      raise HttpError, "Invalid JSON from #{url}: #{e.message}"
    end

    def post_json(url, payload)
      curl!(url, method: "POST", body: JSON.generate(payload))
    end

    def curl!(url, method: nil, body: nil)
      command = ["curl", "-fsSL"]
      command.concat(default_headers.flat_map { |header| ["-H", header] })
      command.concat(["-X", method]) if method
      command.concat(["-d", body]) if body
      command << url

      stdout, stderr, status = Open3.capture3(*command)
      raise HttpError, "curl failed for #{url}: #{stderr.strip}" unless status.success?

      stdout
    rescue Errno::ENOENT => e
      raise CommandError, "Missing required command: curl (#{e.message})"
    end

    def forgejo?
      platform == "forgejo"
    end

    def github?
      platform == "github"
    end
  end

  class ReviewRunner
    MODULE_ROOT = Pathname.new(__dir__).expand_path
    REPO_ROOT = MODULE_ROOT.join("../..").expand_path
    RUBRIC_PATH = MODULE_ROOT.join("upstream_review_prompt.md")
    SCHEMA_PATH = MODULE_ROOT.join("review_output_schema.json")

    attr_reader :api_base_url, :output_dir, :platform, :pr_number, :repo

    def initialize(platform:, repo:, pr_number:, output_dir: nil, api_base_url: nil)
      @platform = platform
      @repo = repo
      @pr_number = pr_number
      @output_dir = Pathname.new(output_dir || REPO_ROOT.join("tmp/codex-pr-review")).expand_path
      @api_base_url = api_base_url
    end

    def run
      reset_output_dir

      pr = client.pull_request
      write_json("pull-request.json", pr)

      prepare_checkout(pr)
      head_sha = pr.fetch("head").fetch("sha")
      base_ref = pr.fetch("base").fetch("ref")
      merge_base_sha = git_capture!("merge-base", head_sha, remote_base_ref(base_ref)).strip
      patch_text = git_capture!("diff", "--no-ext-diff", "--unified=3", merge_base_sha, head_sha)
      write_text("diff.patch", patch_text)

      prompt = self.class.build_review_prompt(
        base_branch: base_ref,
        head_sha: head_sha,
        merge_base_sha: merge_base_sha,
        rubric: rubric_text
      )
      write_text("prompt.txt", prompt)

      output = run_codex(prompt)
      write_json("review-output.json", output)

      diff_map = self.class.diff_map_from_patch(patch_text)
      placed, unplaced = self.class.partition_findings(
        output.fetch("findings"),
        diff_map,
        repo_root: REPO_ROOT.to_s
      )

      top_level_comment = self.class.top_level_comment_body(
        reviewed_at: Time.now.utc.iso8601,
        reviewed_sha: head_sha,
        output: output,
        unplaced_findings: unplaced,
        inline_count: placed.length
      )
      write_text("top-level-comment.md", top_level_comment)

      inline_comments = placed.map { |placement| self.class.inline_comment_payload(placement) }
      write_json("inline-comments.json", inline_comments)

      client.post_top_level_comment(top_level_comment)
      client.post_inline_comments(head_sha: head_sha, comments: inline_comments)

      output
    end

    def self.build_review_prompt(base_branch:, head_sha:, merge_base_sha:, rubric:)
      <<~PROMPT
        Review the code changes against the base branch '#{base_branch}'.
        The current pull request head commit is #{head_sha}.
        The merge base commit for this comparison is #{merge_base_sha}.
        Run `git diff --no-ext-diff --unified=3 #{merge_base_sha} HEAD` to inspect the changes relative to #{base_branch}.
        Return prioritized, actionable findings only. Do not return praise, summaries without findings, or style-only nits. If there are no actionable findings, return an empty findings list and explain why the patch is correct.

        #{rubric}
      PROMPT
    end

    def self.diff_map_from_patch(patch_text)
      changed_lines_by_path = Hash.new { |hash, key| hash[key] = Set.new }
      current_path = nil
      old_line = nil
      new_line = nil

      patch_text.each_line do |line|
        case line
        when /\Adiff --git /
          current_path = nil
          old_line = nil
          new_line = nil
        when /\A\+\+\+ (.+)\n?\z/
          current_path = normalize_patch_path(Regexp.last_match(1))
        when /\A@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/
          old_line = Regexp.last_match(1).to_i
          new_line = Regexp.last_match(2).to_i
        else
          next unless current_path && old_line && new_line

          case line[0]
          when " "
            changed_lines_by_path[current_path] << new_line
            old_line += 1
            new_line += 1
          when "+"
            changed_lines_by_path[current_path] << new_line
            new_line += 1
          when "-"
            old_line += 1
          when "\\"
            next
          end
        end
      end

      changed_lines_by_path
    end

    def self.partition_findings(findings, diff_map, repo_root:)
      placed = []
      unplaced = []

      findings.each do |finding|
        placement = placement_for_finding(finding, diff_map, repo_root: repo_root)
        if placement
          placed << placement.merge("finding" => finding)
        else
          unplaced << finding
        end
      end

      [placed, unplaced]
    end

    def self.inline_comment_payload(placement)
      finding = placement.fetch("finding")

      {
        body: inline_comment_body(finding),
        path: placement.fetch("path"),
        line: placement.fetch("line")
      }
    end

    def self.top_level_comment_body(reviewed_at:, reviewed_sha:, output:, unplaced_findings:, inline_count:)
      priority_counts = counts_by_priority(output.fetch("findings"))
      lines = []
      lines << "## Codex Review"
      lines << ""
      lines << "- Reviewed at: `#{reviewed_at}`"
      lines << "- Reviewed head SHA: `#{reviewed_sha}`"
      lines << "- Verdict: `#{output.fetch("overall_correctness")}`"
      lines << "- Confidence: `#{format("%.2f", output.fetch("overall_confidence_score").to_f)}`"
      lines << "- Priority counts: `P0=#{priority_counts.fetch(0)} P1=#{priority_counts.fetch(1)} P2=#{priority_counts.fetch(2)} P3=#{priority_counts.fetch(3)}`"
      lines << "- Inline findings posted: `#{inline_count}`"
      lines << "- Unplaced findings: `#{unplaced_findings.length}`"
      lines << ""
      lines << output.fetch("overall_explanation")

      if output.fetch("findings").empty?
        lines << ""
        lines << "No actionable findings."
      end

      unless unplaced_findings.empty?
        lines << ""
        lines << "### Unplaced findings"
        unplaced_findings.each do |finding|
          location = finding.fetch("code_location")
          file_path = location.fetch("absolute_file_path")
          line_range = location.fetch("line_range")
          lines << "- **#{finding.fetch("title")}** (`#{file_path}:#{line_range.fetch("start")}`) #{finding.fetch("body")}"
        end
      end

      lines.join("\n")
    end

    def self.inline_comment_body(finding)
      [
        "**#{finding.fetch("title")}**",
        "",
        finding.fetch("body"),
        "",
        "Confidence: `#{format("%.2f", finding.fetch("confidence_score").to_f)}`"
      ].join("\n")
    end

    def self.counts_by_priority(findings)
      counts = (0..3).to_h { |priority| [priority, 0] }
      findings.each do |finding|
        priority = Integer(finding.fetch("priority"))
        counts[priority] += 1
      end
      counts
    end

    def self.placement_for_finding(finding, diff_map, repo_root:)
      location = finding.fetch("code_location")
      relative_path = relative_repo_path(location.fetch("absolute_file_path"), repo_root: repo_root)
      return nil unless relative_path

      changed_lines = diff_map[relative_path]
      return nil if changed_lines.nil? || changed_lines.empty?

      range = location.fetch("line_range")
      start_line = Integer(range.fetch("start"))
      end_line = Integer(range.fetch("end"))
      line = (start_line..end_line).find { |candidate| changed_lines.include?(candidate) }
      return nil unless line

      { "path" => relative_path, "line" => line }
    rescue ArgumentError, KeyError
      nil
    end

    def self.relative_repo_path(path, repo_root:)
      pathname = Pathname.new(path)
      relative =
        if pathname.absolute?
          pathname.relative_path_from(Pathname.new(repo_root)).to_s
        else
          pathname.cleanpath.to_s
        end

      return nil if relative.start_with?("../")

      relative
    rescue ArgumentError
      nil
    end

    def self.normalize_patch_path(raw_path)
      return nil if raw_path == "/dev/null"

      raw_path.sub(%r{\A[ab]/}, "")
    end

    private

    def client
      @client ||= PlatformClient.new(
        platform: platform,
        repo: repo,
        pr_number: pr_number,
        token: api_token,
        api_base_url: api_base_url
      )
    end

    def api_token
      env_name = platform == "github" ? "GITHUB_TOKEN" : "FORGEJO_BOT_TOKEN"
      ENV.fetch(env_name)
    rescue KeyError
      raise Error, "Missing required environment variable #{env_name}"
    end

    def rubric_text
      @rubric_text ||= RUBRIC_PATH.read
    end

    def reset_output_dir
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)
    end

    def run_codex(prompt)
      review_output_path = output_dir.join("codex-review.json")
      stdout, stderr, status = Open3.capture3(
        "codex", "exec",
        "--sandbox", "read-only",
        "--output-schema", SCHEMA_PATH.to_s,
        "--output-last-message", review_output_path.to_s,
        "-",
        stdin_data: prompt
      )
      write_text("codex-stdout.log", stdout)
      write_text("codex-stderr.log", stderr)

      raise Error, "codex exec failed: #{stderr.strip}" unless status.success?
      raise Error, "codex exec did not write #{review_output_path}" unless review_output_path.file?

      JSON.parse(review_output_path.read)
    rescue Errno::ENOENT => e
      raise CommandError, "Missing required command: codex (#{e.message})"
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON from codex exec: #{e.message}"
    end

    def prepare_checkout(pr)
      base_ref = pr.fetch("base").fetch("ref")
      head_sha = pr.fetch("head").fetch("sha")
      head_ref = pr.fetch("head").fetch("ref")
      head_clone_url = pr.dig("head", "repo", "clone_url")

      fetch_base_branch(base_ref)
      ensure_head_commit(head_sha: head_sha, head_ref: head_ref, head_clone_url: head_clone_url)
      git!("checkout", "--detach", head_sha)
      write_text("checked-out-head.txt", head_sha)
    end

    def ensure_head_commit(head_sha:, head_ref:, head_clone_url:)
      return if commit_exists?(head_sha)

      if platform == "github"
        fetch_spec("origin", "pull/#{pr_number}/head:refs/codex-pr-review/#{pr_number}")
      else
        fetch_spec("origin", "#{head_ref}:refs/codex-pr-review/#{pr_number}") if head_ref
      end
      return if commit_exists?(head_sha)

      if head_ref
        fetch_spec("origin", head_ref)
        return if commit_exists?(head_sha)
      end

      if head_clone_url && head_ref
        remote_name = "codex-pr-review-head"
        git!("remote", "remove", remote_name) if remote_exists?(remote_name)
        git!("remote", "add", remote_name, head_clone_url)
        fetch_spec(remote_name, head_ref)
      end
    ensure
      git!("remote", "remove", "codex-pr-review-head") if remote_exists?("codex-pr-review-head")

      raise Error, "Unable to fetch PR head commit #{head_sha}" unless commit_exists?(head_sha)
    end

    def fetch_base_branch(base_ref)
      fetch_spec("origin", "refs/heads/#{base_ref}:#{remote_base_ref(base_ref)}")
    end

    def remote_base_ref(base_ref)
      "refs/remotes/origin/#{base_ref}"
    end

    def fetch_spec(remote, spec)
      git!("fetch", "--no-tags", remote, spec)
    end

    def commit_exists?(sha)
      _stdout, _stderr, status = Open3.capture3("git", "cat-file", "-e", "#{sha}^{commit}", chdir: REPO_ROOT.to_s)
      status.success?
    end

    def remote_exists?(name)
      stdout, _stderr, status = Open3.capture3("git", "remote", chdir: REPO_ROOT.to_s)
      status.success? && stdout.lines.map(&:strip).include?(name)
    end

    def git!(*args)
      _stdout, stderr, status = Open3.capture3("git", *args, chdir: REPO_ROOT.to_s)
      raise CommandError, "git #{args.join(' ')} failed: #{stderr.strip}" unless status.success?
    rescue Errno::ENOENT => e
      raise CommandError, "Missing required command: git (#{e.message})"
    end

    def git_capture!(*args)
      stdout, stderr, status = Open3.capture3("git", *args, chdir: REPO_ROOT.to_s)
      raise CommandError, "git #{args.join(' ')} failed: #{stderr.strip}" unless status.success?

      stdout
    rescue Errno::ENOENT => e
      raise CommandError, "Missing required command: git (#{e.message})"
    end

    def write_json(name, payload)
      write_text(name, JSON.pretty_generate(payload))
    end

    def write_text(name, contents)
      File.write(output_dir.join(name), contents)
    end
  end

  class Cli
    def initialize(argv:, stdout: $stdout, stderr: $stderr)
      @argv = argv
      @stdout = stdout
      @stderr = stderr
    end

    def run
      options = parse_options
      runner = ReviewRunner.new(**options)
      output = runner.run
      stdout.puts(JSON.pretty_generate(output))
    rescue Error, OptionParser::ParseError => e
      stderr.puts(e.message)
      exit(1)
    end

    private

    attr_reader :argv, :stderr, :stdout

    def parse_options
      parsed = { output_dir: nil, repo: nil, pr_number: nil, api_base_url: nil }

      OptionParser.new do |parser|
        parser.banner = "Usage: ruby bin/codex-pr-review --platform <forgejo|github> [options]"
        parser.on("--platform PLATFORM", %w[forgejo github]) { |value| parsed[:platform] = value }
        parser.on("--repo REPO") { |value| parsed[:repo] = value }
        parser.on("--pr-number NUMBER", Integer) { |value| parsed[:pr_number] = value }
        parser.on("--output-dir DIR") { |value| parsed[:output_dir] = value }
        parser.on("--api-base-url URL") { |value| parsed[:api_base_url] = value }
      end.parse!(argv)

      parsed[:repo] ||= ENV["GITHUB_REPOSITORY"] || event_payload.dig("repository", "full_name")
      parsed[:pr_number] ||= infer_pr_number(event_payload)

      raise OptionParser::ParseError, "missing --platform" unless parsed[:platform]
      raise OptionParser::ParseError, "missing --repo and GITHUB_REPOSITORY" unless parsed[:repo]
      raise OptionParser::ParseError, "missing --pr-number and no pull request number in event payload" unless parsed[:pr_number]

      parsed
    end

    def event_payload
      @event_payload ||= begin
        path = ENV["GITHUB_EVENT_PATH"]
        if path && File.file?(path)
          JSON.parse(File.read(path))
        else
          {}
        end
      rescue JSON::ParserError
        {}
      end
    end

    def infer_pr_number(payload)
      value = payload["number"] || payload.dig("pull_request", "number") || payload.dig("inputs", "pr_number")
      Integer(value, exception: false)
    end
  end
end
