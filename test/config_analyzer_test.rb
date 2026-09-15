require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rails_preflight/config_analyzer"

class ConfigAnalyzerTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@tmp_dir, "config", "initializers"))
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def test_current_load_defaults_passes_without_new_framework_defaults
    write_application_rb("config.load_defaults 7.1")

    result = RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "7.1.3").run

    assert_equal :passed, result[:status], "Unexpected findings: #{result[:checks]}"
  end

  def test_flags_load_defaults_behind_current_rails
    write_application_rb('config.load_defaults "5.2"')

    result = RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "7.1.3").run

    assert_equal :warning, result[:status]
    assert_includes messages(result), "CONFIG: load_defaults 5.2 is behind Rails 7.1: framework defaults added after 5.2 are not enabled."
  end

  def test_mentions_new_framework_defaults_when_catch_up_is_in_progress
    write_application_rb("config.load_defaults 7.0")
    File.write(File.join(@tmp_dir, "config", "initializers", "new_framework_defaults_7_1.rb"), "")

    result = RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "7.1.3").run

    assert_includes messages(result).join, "Found new_framework_defaults_7_1.rb, so enabling them looks in progress."
  end

  def test_missing_load_defaults_is_expected_before_rails_5_1
    write_application_rb("config.time_zone = 'UTC'")

    assert_equal :passed, RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "5.0.7").run[:status]
    assert_includes messages(RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "6.1.7").run).join, "'config.load_defaults' missing"
  end

  private

  def write_application_rb(line)
    File.write(File.join(@tmp_dir, "config", "application.rb"), <<~RUBY)
      module App
        class Application < Rails::Application
          #{line}
        end
      end
    RUBY
  end

  def messages(result)
    result[:checks].map { |c| c[:message] }
  end
end
