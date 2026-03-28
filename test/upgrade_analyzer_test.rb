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

    RailsPreflight::UpgradeAnalyzer.new("8.0", @tmp_dir).run

    report_path = File.join(@tmp_dir, "rails_preflight_report.html")
    assert File.exist?(report_path)
    assert_includes File.read(report_path), "Unknown Rails version: 8.0"
  end

  def test_missing_lockfile_is_reported_without_crashing
    FileUtils.mkdir_p(File.join(@tmp_dir, "config"))
    File.write(File.join(@tmp_dir, "config", "application.rb"), "config.load_defaults 6.1\n")

    RailsPreflight::UpgradeAnalyzer.new("6.1", @tmp_dir).run

    report_path = File.join(@tmp_dir, "rails_preflight_report.html")
    assert File.exist?(report_path)
    assert_includes File.read(report_path), "No Gemfile.lock found. Skipping gem compatibility checks."
  end

  private

  def write_lockfile
    File.write(File.join(@tmp_dir, "Gemfile.lock"), <<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.0.6)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake

      BUNDLED WITH
         2.7.2
    LOCKFILE
  end
end
