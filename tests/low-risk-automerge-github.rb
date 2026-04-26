#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

require_relative "../tools/low-risk-automerge/common"
require_relative "../tools/low-risk-automerge/github"

module LowRiskAutomerge
  class MetadataParserTest < Minitest::Test
    VALID_BODY = <<~MARKDOWN
      <!-- codex-review:v1
      reviewed_head: abc123
      risk: low
      merge_ok: true
      reviewer: codex-pr-review
      -->

      ## Codex Review
    MARKDOWN

    def test_valid_metadata_parses
      metadata = MetadataParser.parse(VALID_BODY)

      assert_equal "abc123", metadata.reviewed_head
      assert_equal "low", metadata.risk
      assert_equal true, metadata.merge_ok
      assert_equal "codex-pr-review", metadata.reviewer
    end

    def test_missing_metadata_returns_nil
      assert_nil MetadataParser.parse("## Codex Review")
    end

    def test_duplicate_metadata_returns_nil
      assert_nil MetadataParser.parse("#{VALID_BODY}\n#{VALID_BODY}")
    end

    def test_unknown_risk_returns_nil
      assert_nil MetadataParser.parse(VALID_BODY.sub("risk: low", "risk: routine"))
    end

    def test_non_boolean_merge_ok_returns_nil
      assert_nil MetadataParser.parse(VALID_BODY.sub("merge_ok: true", "merge_ok: yes"))
    end
  end

  class GitHubAutomergeTest < Minitest::Test
    def setup
      @client = FakeGitHubClient.new
      @runner = GitHubRunner.new(repo: "owner/repo", client: @client, bot_author: "github-actions[bot]")
    end

    def test_rejects_fork_pull_request
      pr = pull_request(head_repo: "other/repo")

      result = @runner.evaluate(pr)

      refute result.merge?
      assert_equal "fork pull request", result.reason
    end

    def test_accepts_non_fork_pr_with_trusted_current_head_low_risk_metadata
      pr = pull_request
      @client.comments[1] = [review_comment(body: metadata_body(reviewed_head: "abc123"))]
      @client.check_runs_by_sha["abc123"] = [{ "name" => "Integration Test", "status" => "completed", "conclusion" => "success" }]
      @client.statuses["abc123"] = { "state" => "success" }

      result = @runner.evaluate(pr)

      assert result.merge?
      assert_nil result.reason
    end

    def test_rejects_untrusted_comment_author
      pr = pull_request
      @client.comments[1] = [review_comment(user: "renovate[bot]", body: metadata_body(reviewed_head: "abc123"))]
      @client.check_runs_by_sha["abc123"] = [{ "name" => "Integration Test", "status" => "completed", "conclusion" => "success" }]
      @client.statuses["abc123"] = { "state" => "success" }

      result = @runner.evaluate(pr)

      refute result.merge?
      assert_equal "no trusted codex review metadata", result.reason
    end

    def test_rejects_stale_reviewed_head
      pr = pull_request
      @client.comments[1] = [review_comment(body: metadata_body(reviewed_head: "oldsha"))]
      @client.check_runs_by_sha["abc123"] = [{ "name" => "Integration Test", "status" => "completed", "conclusion" => "success" }]
      @client.statuses["abc123"] = { "state" => "success" }

      result = @runner.evaluate(pr)

      refute result.merge?
      assert_equal "review metadata is stale", result.reason
    end

    def test_rejects_failed_or_pending_check_runs
      pr = pull_request
      @client.comments[1] = [review_comment(body: metadata_body(reviewed_head: "abc123"))]
      @client.check_runs_by_sha["abc123"] = [
        { "name" => "Integration Test", "status" => "completed", "conclusion" => "failure" },
        { "name" => "Codex PR Review", "status" => "in_progress", "conclusion" => nil }
      ]
      @client.statuses["abc123"] = { "state" => "success" }

      result = @runner.evaluate(pr)

      refute result.merge?
      assert_match(/check runs not successful/, result.reason)
    end

    def test_rejects_failed_combined_status
      pr = pull_request
      @client.comments[1] = [review_comment(body: metadata_body(reviewed_head: "abc123"))]
      @client.check_runs_by_sha["abc123"] = [{ "name" => "Integration Test", "status" => "completed", "conclusion" => "success" }]
      @client.statuses["abc123"] = { "state" => "failure" }

      result = @runner.evaluate(pr)

      refute result.merge?
      assert_equal "combined status is failure", result.reason
    end

    def test_posts_refusal_comment_on_blocked_merge
      @client.prs = [pull_request(head_repo: "other/repo")]

      @runner.run(pr_number: 1)

      assert_equal "/issues/1/comments", @client.posts.first.fetch(:path)
      assert_match(/Low-risk automerge skipped: fork pull request/, @client.posts.first.fetch(:payload).fetch("body"))
    end

    def test_does_not_duplicate_existing_refusal_comment
      @client.prs = [pull_request(head_repo: "other/repo")]
      @client.comments[1] = [
        review_comment(
          body: "<!-- low-risk-automerge:v1 -->\nLow-risk automerge skipped: fork pull request"
        )
      ]

      @runner.run(pr_number: 1)

      assert_empty @client.posts
    end

    def test_cli_ignores_non_pr_issue_comment_events
      path = write_event_payload({ "issue" => { "number" => 99 } })
      old_path = ENV["LOW_RISK_AUTOMERGE_EVENT_PATH"]
      ENV["LOW_RISK_AUTOMERGE_EVENT_PATH"] = path

      assert_equal :no_pr_event, Cli.new(argv: []).send(:parse_pr_number)
    ensure
      ENV["LOW_RISK_AUTOMERGE_EVENT_PATH"] = old_path
      FileUtils.rm_f(path) if path
    end

    def test_sends_rebase_merge_request_with_current_head_sha
      @client.prs = [pull_request]
      @client.comments[1] = [review_comment(body: metadata_body(reviewed_head: "abc123"))]
      @client.check_runs_by_sha["abc123"] = [{ "name" => "Integration Test", "status" => "completed", "conclusion" => "success" }]
      @client.statuses["abc123"] = { "state" => "success" }

      @runner.run(pr_number: 1)

      assert_equal "/pulls/1/merge", @client.puts.first.fetch(:path)
      assert_equal({ "sha" => "abc123", "merge_method" => "rebase" }, @client.puts.first.fetch(:payload))
    end

    private

    def pull_request(number: 1, head_sha: "abc123", head_repo: "owner/repo", base_repo: "owner/repo")
      {
        "number" => number,
        "head" => { "sha" => head_sha, "repo" => { "full_name" => head_repo } },
        "base" => { "repo" => { "full_name" => base_repo } }
      }
    end

    def review_comment(user: "github-actions[bot]", body:)
      {
        "user" => { "login" => user },
        "body" => body,
        "created_at" => "2026-04-26T18:00:00Z"
      }
    end

    def metadata_body(reviewed_head:)
      MetadataParserTest::VALID_BODY.sub("reviewed_head: abc123", "reviewed_head: #{reviewed_head}")
    end

    def write_event_payload(payload)
      path = File.join(Dir.mktmpdir("low-risk-automerge-event"), "event.json")
      File.write(path, JSON.generate(payload))
      path
    end
  end

  class FakeGitHubClient
    attr_accessor :prs
    attr_reader :comments, :posts, :puts, :statuses

    def initialize
      @prs = []
      @comments = {}
      @check_runs = {}
      @statuses = {}
      @posts = []
      @puts = []
    end

    def open_pull_requests
      prs
    end

    def pull_request(number)
      prs.find { |pr| pr.fetch("number") == number }
    end

    def issue_comments(number)
      comments.fetch(number, [])
    end

    def check_runs(head_sha)
      { "check_runs" => @check_runs.fetch(head_sha, []) }
    end

    def check_runs_by_sha
      @check_runs
    end

    def combined_status(head_sha)
      statuses.fetch(head_sha, { "state" => "success" })
    end

    def post_json(path, payload)
      posts << { path: path, payload: payload }
    end

    def put_json(path, payload)
      puts << { path: path, payload: payload }
    end
  end
end
