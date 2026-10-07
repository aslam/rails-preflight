require "minitest/autorun"
require "tmpdir"
require "fileutils"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rails_preflight"

class GemAnalyzerTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def test_locked_rails_limit_blocks_the_hop_it_excludes
    specs = lockfile_specs("devise (4.7.1)\n      railties (>= 4.1.0, < 6.1)")

    check = run_checks(specs, hops: %w[6.0 6.1 7.0]).first

    assert_equal :failed, check[:status]
    assert_equal "6.1", check[:removed_in]
    assert_includes check[:message], "devise 4.7.1 requires railties >= 4.1.0, < 6.1"
  end

  def test_locked_limits_allow_any_patch_of_a_minor_and_skip_rails_itself
    specs = lockfile_specs("pundit (2.3.0)\n      activesupport (>= 7.0.1)", "actionpack (7.0.8)\n      activesupport (= 7.0.8)")

    assert_equal [], run_checks(specs, hops: %w[7.0 7.1]).map { |c| c[:message] }.grep(/requires/)
  end

  def test_adapter_outside_rails_range_blocks_the_first_hop_that_rejects_it
    specs = lockfile_specs("sqlite3 (1.3.13)", "pg (1.0.0)", "mysql2 (0.5.6)")

    checks = run_checks(specs, hops: %w[6.0 6.1 7.0])

    assert_equal [["6.0", "sqlite3 1.3.13 doesn't load on Rails 6.0, which requires sqlite3 ~> 1.4. Upgrade it in the same step."],
                  ["6.1", "pg 1.0.0 doesn't load on Rails 6.1, which requires pg ~> 1.1. Upgrade it in the same step."]],
                 checks.map { |c| [c[:removed_in], c[:message]] }.sort
  end

  def test_gem_rails_stops_depending_on_blocks_unless_the_gemfile_lists_it
    write_app_file("config/application.rb", "require 'rails/all'\n    config.assets.enabled = false\n")
    specs = lockfile_specs("sprockets-rails (3.2.2)")

    check = RailsPreflight::GemAnalyzer.new(@tmp_dir, specs, hops: %w[6.1 7.0], direct: %w[rails]).run[:checks].first
    listed = RailsPreflight::GemAnalyzer.new(@tmp_dir, specs, hops: %w[6.1 7.0], direct: %w[rails sprockets-rails]).run[:checks]
    via_sass = RailsPreflight::GemAnalyzer.new(@tmp_dir, lockfile_specs("sprockets-rails (3.2.2)", "sass-rails (5.1.0)\n      sprockets-rails (>= 2.0, < 4.0)"), hops: %w[7.0], direct: %w[rails sass-rails]).run[:checks]

    assert_equal "7.0", check[:removed_in]
    assert_includes check[:message], "Rails 7.0 no longer depends on sprockets-rails"
    assert_equal [], (listed + via_sass).map { |c| c[:message] }.grep(/sprockets/)
  end

  def test_gem_rails_stops_depending_on_is_fine_when_the_app_never_uses_it
    write_app_file("config/application.rb", "# require 'sprockets/railtie'\n    # config.assets.enabled = false\n")
    specs = lockfile_specs("sprockets-rails (3.2.2)")

    assert_equal [], run_checks(specs, hops: %w[7.0]).map { |c| c[:message] }.grep(/sprockets/)

    write_app_file("app/assets/config/manifest.js", "//= link_tree ../images\n")
    assert_equal 1, run_checks(specs, hops: %w[7.0]).map { |c| c[:message] }.grep(/sprockets/).size
  end

  def test_curated_gem_blocks_the_hop_where_it_stops_working
    write_app_file("app/models/user.rb", "  attr_accessible :name\n  attr_accessor :token\n")
    write_app_file("app/models/post.rb", "  attr_protected :id\n")
    specs = lockfile_specs("protected_attributes_continued (1.9.0)\n      activemodel (>= 5.0)")

    check = run_checks(specs, hops: %w[6.1 7.0]).first

    assert_equal :failed, check[:status]
    assert_equal "7.0", check[:removed_in]
    assert_includes check[:message], "Used in 2 files."
    assert_equal ["Source: https://github.com/westonganger/protected_attributes_continued#readme", "app/models/post.rb", "app/models/user.rb"], check[:details]
  end

  def test_curated_gem_past_the_target_is_a_deadline
    specs = lockfile_specs("protected_attributes_continued (1.9.0)")

    check = run_checks(specs, hops: %w[6.0]).first

    assert_equal :warning, check[:status]
    assert_equal "7.0", check[:removed_in]
    assert_includes check[:message], "It doesn't work from Rails 7.0, so plan the move before then. Used in 0 files."
  end

  def test_version_and_usage_conditions_narrow_an_entry
    write_app_file("config/application.rb", "config.active_job.queue_adapter = :que\n")

    old = run_checks(lockfile_specs("que (1.4.1)"), hops: %w[7.1]).first
    fixed = run_checks(lockfile_specs("que (2.3.0)"), hops: %w[7.1])

    assert_equal "7.1", old[:removed_in]
    assert_includes old[:message], "que 1.4.1 runs Active Job"
    assert_equal [], fixed.map { |c| c[:message] }.grep(/que/)

    File.write(File.join(@tmp_dir, "config/application.rb"), "config.active_job.queue_adapter = :sidekiq\n")
    assert_equal [], run_checks(lockfile_specs("que (1.4.1)"), hops: %w[7.1]).map { |c| c[:message] }.grep(/que/)
  end

  def test_curated_gem_past_its_limit_on_the_current_rails_is_already_broken
    check = run_checks(lockfile_specs("protected_attributes_continued (1.9.0)"), hops: %w[7.1]).first

    assert_equal :broken, check[:kind]
    assert_includes check[:message], "which this app is already on"
  end

  def test_gems_not_released_since_before_the_target_are_grouped_oldest_first
    specs = lockfile_specs("devise (4.7.1)\n      railties (>= 4.1.0, < 6.1)")
    releases = { "acts_as_list" => "2019-03-01T10:00:00Z", "paperclip" => "2018-07-27T19:55:32Z", "kaminari" => "2023-12-01T00:00:00Z",
                 "rails_admin_tag" => "2017-05-02T00:00:00Z", "devise" => "2020-01-01T00:00:00Z" }

    check = RailsPreflight::GemAnalyzer.new(@tmp_dir, specs, hops: %w[6.1 7.0], last_releases: releases, target_released: "2021-12-15").run[:checks].last

    assert_equal :unknown, check[:kind]
    assert_includes check[:message], "2 gems that depend on Rails had no release since before Rails 7.0 shipped (2021-12-15)"
    # devise is already a blocker and paperclip is on the curated list, so neither is repeated
    assert_equal ["rails_admin_tag (last release 2017-05-02)", "acts_as_list (last release 2019-03-01)"], check[:details]
  end

  def test_release_date_check_says_when_it_was_skipped
    checks = RailsPreflight::GemAnalyzer.new(@tmp_dir, [], hops: %w[7.0], last_releases: nil, target_released: "2021-12-15").run[:checks]
    unknown_target = RailsPreflight::GemAnalyzer.new(@tmp_dir, [], hops: %w[9.0], last_releases: { "old" => "2010-01-01T00:00:00Z" }).run[:checks]

    assert_equal :tip, checks.last[:kind]
    assert_includes checks.last[:message], "--offline"
    assert_equal [], unknown_target.map { |c| c[:message] }.grep(/no release since/)
  end

  def test_retired_gem_is_to_fix_without_a_hop
    specs = lockfile_specs("therubyracer (0.12.3)")

    check = run_checks(specs, hops: %w[7.0]).first

    assert_equal :warning, check[:status]
    assert_nil check[:removed_in]
    refute_includes check[:message], "Used in"
  end

  def test_every_curated_pattern_compiles_and_has_a_source
    YAML.load_file(RailsPreflight::GemAnalyzer::DATA_PATH)["gems"].each do |entry|
      Regexp.new(entry["pattern"]) if entry["pattern"]
      assert entry["source"].start_with?("https://"), "#{entry['name']} needs a source"
      assert entry["pattern"], "#{entry['name']} is only_if_used, so it needs a pattern" if entry["only_if_used"]
    end
  end

  def test_nothing_to_report_passes
    result = RailsPreflight::GemAnalyzer.new(@tmp_dir, lockfile_specs("rake (13.0.6)"), hops: %w[7.0]).run

    assert_equal :passed, result[:status]
  end

  private

  def run_checks(specs, hops:)
    RailsPreflight::GemAnalyzer.new(@tmp_dir, specs, hops: hops).run[:checks]
  end

  def lockfile_specs(*specs)
    Bundler::LockfileParser.new(<<~LOCKFILE).specs
      GEM
        remote: https://rubygems.org/
        specs:
      #{specs.map { |s| "    #{s}" }.join("\n")}

      PLATFORMS
        ruby

      DEPENDENCIES
        rake
    LOCKFILE
  end

  def write_app_file(path, content)
    full = File.join(@tmp_dir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end
end
