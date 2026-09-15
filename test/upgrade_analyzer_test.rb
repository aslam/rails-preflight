require "minitest/autorun"
require "tmpdir"
require "fileutils"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rails_preflight"

class UpgradeAnalyzerTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def test_unknown_target_rails_generates_a_report_instead_of_crashing
    write_lockfile

    RailsPreflight::UpgradeAnalyzer.new("9.0", @tmp_dir).run

    report_path = File.join(@tmp_dir, "rails_preflight_report.html")
    assert File.exist?(report_path)
    assert_includes File.read(report_path), "Unknown Rails version: 9.0"
  end

  def test_rails_8_1_accepts_ruby_4_0
    write_lockfile
    File.write(File.join(@tmp_dir, ".ruby-version"), "4.0.1\n")

    RailsPreflight::UpgradeAnalyzer.new("8.1", @tmp_dir).run

    assert_includes File.read(File.join(@tmp_dir, "rails_preflight_report.html")), "Ruby 4.0.1 (.ruby-version) is compatible with Rails 8.1."
  end

  def test_missing_lockfile_is_reported_without_crashing
    FileUtils.mkdir_p(File.join(@tmp_dir, "config"))
    File.write(File.join(@tmp_dir, "config", "application.rb"), "config.load_defaults 6.1\n")

    RailsPreflight::UpgradeAnalyzer.new("6.1", @tmp_dir).run

    report_path = File.join(@tmp_dir, "rails_preflight_report.html")
    assert File.exist?(report_path)
    assert_includes File.read(report_path), "No Gemfile.lock found. Skipping gem compatibility checks."
  end

  def test_two_part_ruby_version_does_not_crash
    File.write(File.join(@tmp_dir, ".ruby-version"), "3.3\n")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Ruby 3.3 (.ruby-version) is compatible with Rails 7.2."
  end

  def test_two_part_dockerfile_ruby_tag_does_not_crash
    File.write(File.join(@tmp_dir, "Dockerfile"), "FROM ruby:3.3-slim\n")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Ruby 3.3 (Dockerfile) is compatible with Rails 7.2."
  end

  def test_reads_ruby_version_from_gemfile_lock
    write_lockfile(ruby: "3.3.5p100")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Ruby 3.3.5 (Gemfile.lock) is compatible with Rails 7.2."
  end

  def test_undetectable_app_ruby_is_reported_not_guessed
    write_lockfile

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Could not determine the Ruby version used by the app"
    refute_includes report, RUBY_VERSION
  end

  def test_reports_current_rails_version_from_lockfile
    write_lockfile(rails: "7.1.3")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Rails 7.1.3 (Gemfile.lock) → 7.2"
    assert_includes report, "Upgrade Rails 7.1.3 → 7.2"
  end

  def test_flags_target_that_is_not_an_upgrade
    write_lockfile(rails: "7.2.1")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Already on Rails 7.2.1: 7.2 is not an upgrade."
  end

  def test_unknown_current_rails_is_reported
    write_lockfile

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Could not read current Rails version from Gemfile.lock."
  end

  private

  def report
    File.read(File.join(@tmp_dir, "rails_preflight_report.html"))
  end

  def write_lockfile(ruby: nil, rails: nil)
    ruby_section = ruby ? "RUBY VERSION\n   ruby #{ruby}\n\n" : ""
    rails_spec = rails ? "\n    railties (#{rails})" : ""
    File.write(File.join(@tmp_dir, "Gemfile.lock"), <<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.0.6)#{rails_spec}

      PLATFORMS
        ruby

      DEPENDENCIES
        rake

      #{ruby_section}BUNDLED WITH
         2.7.2
    LOCKFILE
  end
end
