#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

require_relative "common"

module LowRiskAutomerge
  Decision = Struct.new(:merge?, :reason, keyword_init: true)

  class GitHubClient
    API_VERSION = "2022-11-28"

    def initialize(repo:, token:, api_url: ENV.fetch("GITHUB_API_URL", "https://api.github.com"))
      @repo = repo
      @token = token
      @api_url = api_url
    end

    def open_pull_requests
      get_json("/pulls?state=open")
    end

    def pull_request(number)
      get_json("/pulls/#{number}")
    end

    def issue_comments(number)
      get_json("/issues/#{number}/comments")
    end

    def check_runs(head_sha)
      get_json("/commits/#{head_sha}/check-runs")
    end

    def combined_status(head_sha)
      get_json("/commits/#{head_sha}/status")
    end

    def get_json(path)
      JSON.parse(curl(path))
    rescue JSON::ParserError => e
      raise HttpError, "Invalid JSON from #{path}: #{e.message}"
    end

    def post_json(path, payload)
      curl(path, method: "POST", body: JSON.generate(payload))
    end

    def put_json(path, payload)
      curl(path, method: "PUT", body: JSON.generate(payload))
    end

    private

    attr_reader :api_url, :repo, :token

    def curl(path, method: nil, body: nil)
      command = [
        "curl", "-fsSL",
        "-H", "Accept: application/vnd.github+json",
        "-H", "Authorization: Bearer #{token}",
        "-H", "X-GitHub-Api-Version: #{API_VERSION}",
        "-H", "Content-Type: application/json"
      ]
      command.concat(["-X", method]) if method
      command.concat(["-d", body]) if body
      command << "#{api_url}/repos/#{repo}#{path}"

      stdout, stderr, status = Open3.capture3(*command)
      raise HttpError, stderr.strip unless status.success?

      stdout
    rescue Errno::ENOENT => e
      raise Error, "Missing required command: curl (#{e.message})"
    end
  end

  class GitHubRunner
    IGNORED_IN_PROGRESS_CHECKS = ["Low-Risk Automerge"].freeze

    def initialize(repo:, client:, bot_author:)
      @repo = repo
      @client = client
      @bot_author = bot_author
    end

    def run(pr_number: nil)
      pull_requests = pr_number ? [client.pull_request(pr_number)] : client.open_pull_requests
      pull_requests.compact.each do |pr|
        result = evaluate(pr)
        if result.merge?
          merge(pr)
        else
          post_refusal(pr.fetch("number"), result.reason)
        end
      end
    end

    def evaluate(pr)
      number = pr.fetch("number")
      head_sha = pr.fetch("head").fetch("sha")
      return blocked("fork pull request") if fork?(pr)

      metadata = trusted_metadata(number)
      return blocked("no trusted codex review metadata") unless metadata
      return blocked("review metadata is stale") unless metadata.reviewed_head == head_sha
      return blocked("review risk is #{metadata.risk}") unless metadata.risk == "low"
      return blocked("review did not approve merge") unless metadata.merge_ok

      check_failure = check_runs_failure(head_sha)
      return blocked(check_failure) if check_failure

      status_state = client.combined_status(head_sha).fetch("state")
      return blocked("combined status is #{status_state}") unless status_state == "success"

      Decision.new(merge?: true)
    end

    private

    attr_reader :bot_author, :client, :repo

    def fork?(pr)
      pr.dig("head", "repo", "full_name") != pr.dig("base", "repo", "full_name")
    end

    def trusted_metadata(number)
      trusted_comments = client.issue_comments(number).select do |comment|
        comment.dig("user", "login") == bot_author
      end
      trusted_comments.reverse_each do |comment|
        metadata = MetadataParser.parse(comment["body"])
        return metadata if metadata
      end
      nil
    end

    def check_runs_failure(head_sha)
      failing = client.check_runs(head_sha).fetch("check_runs", []).reject do |check_run|
        check_successful?(check_run) || ignored_in_progress_check?(check_run)
      end
      return nil if failing.empty?

      names = failing.map { |check_run| check_run.fetch("name") }.join(", ")
      "check runs not successful: #{names}"
    end

    def check_successful?(check_run)
      check_run["status"] == "completed" && check_run["conclusion"] == "success"
    end

    def ignored_in_progress_check?(check_run)
      IGNORED_IN_PROGRESS_CHECKS.include?(check_run["name"]) && check_run["status"] == "in_progress"
    end

    def merge(pr)
      number = pr.fetch("number")
      head_sha = pr.fetch("head").fetch("sha")
      client.put_json("/pulls/#{number}/merge", { "sha" => head_sha, "merge_method" => "rebase" })
    end

    def post_refusal(number, reason)
      client.post_json("/issues/#{number}/comments", { "body" => "Low-risk automerge skipped: #{reason}" })
    end

    def blocked(reason)
      Decision.new(merge?: false, reason: reason)
    end
  end

  class Cli
    def initialize(argv:)
      @argv = argv
    end

    def run
      pr_number = parse_pr_number
      repo = ENV.fetch("LOW_RISK_AUTOMERGE_REPO") { ENV.fetch("GITHUB_REPOSITORY") }
      token = ENV.fetch("GITHUB_TOKEN")
      bot_author = ENV.fetch("LOW_RISK_AUTOMERGE_BOT_AUTHOR", "github-actions[bot]")

      client = GitHubClient.new(repo: repo, token: token)
      GitHubRunner.new(repo: repo, client: client, bot_author: bot_author).run(pr_number: pr_number)
    rescue Error, KeyError, OptionParser::ParseError => e
      warn e.message
      exit(1)
    end

    private

    attr_reader :argv

    def parse_pr_number
      options = { pr_number: nil }
      OptionParser.new do |parser|
        parser.on("--pr-number NUMBER", Integer) { |value| options[:pr_number] = value }
      end.parse!(argv)

      options[:pr_number] || event_pr_number
    end

    def event_pr_number
      path = ENV["LOW_RISK_AUTOMERGE_EVENT_PATH"] || ENV["GITHUB_EVENT_PATH"]
      return nil unless path && File.file?(path)

      payload = JSON.parse(File.read(path))
      value = payload.dig("inputs", "pr_number") ||
              payload.dig("issue", "pull_request") && payload.dig("issue", "number") ||
              payload.dig("pull_request", "number")
      Integer(value, exception: false)
    rescue JSON::ParserError
      nil
    end
  end
end

LowRiskAutomerge::Cli.new(argv: ARGV).run if $PROGRAM_NAME == __FILE__
