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
    assert_includes messages(result), "load_defaults 5.2 is behind Rails 7.1: framework defaults added after 5.2 are not enabled."
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
    assert_includes messages(RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "6.1.7").run).join, "config.load_defaults missing"
  end

  def test_flags_committed_secrets_by_key_never_value
    write_config "storage.yml", <<~YAML
      amazon:
        service: S3
        access_key_id: AKIAEXAMPLE123
        "secret_access_key": 'wJalrXUtnFEMI'
        bucket: app-uploads
    YAML

    secrets = checks(RailsPreflight::ConfigAnalyzer.new(@tmp_dir).run).find { |c| c[:message].include?("committed") }
    assert_equal "2 secrets are committed in config YAML, where anyone with the repository can read them. Rotate them, and read them from credentials or ENV instead.", secrets[:message]
    assert_equal [{ file: "config/storage.yml", line: 3, snippet: "access_key_id: [hidden]" },
                  { file: "config/storage.yml", line: 4, snippet: "secret_access_key: [hidden]" }], secrets[:files]
    refute_includes secrets.to_s, "AKIAEXAMPLE123"
  end

  # The shapes Rails generates, plus values that hold no secret.
  def test_skips_erb_local_sections_locales_and_non_literals
    write_config "database.yml", <<~YAML
      default: &default
        password: <%= ENV["DATABASE_PASSWORD"] %>
      development:
        password: postgres
      test:
        password: postgres
      production:
        <<: *default
        password: "<%= ENV.fetch('DB_PASSWORD') %>"
        password_reset: true
        token_ttl: 3600 # seconds
        api_key: ""
        api_key_other: ~
    YAML
    write_config "locales/en.yml", "en:\n  password: Password\n"

    assert_equal [], checks(RailsPreflight::ConfigAnalyzer.new(@tmp_dir).run).select { |c| c[:files] }
  end

  def test_secrets_yml_secret_key_base_blocks_rails_7_2
    write_config "secrets.yml", <<~YAML
      development:
        secret_key_base: d4391b
      production:
        secret_key_base: <%= ENV["RAILS_SECRET"] %>
    YAML

    finding = checks(RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "6.1.7", target_rails: "7.2").run).find { |c| c[:removed_in] }
    assert_equal :failed, finding[:status]
    assert_equal [{ file: "config/secrets.yml", line: 4, snippet: "secret_key_base: [hidden]" }], finding[:files]
    assert_equal :warning, checks(RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "6.1.7", target_rails: "7.1").run).find { |c| c[:removed_in] }[:status]
    assert_nil checks(RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "7.2.1", target_rails: "8.0").run).find { |c| c[:removed_in] }
  end

  # Rails 7.2 reads SECRET_KEY_BASE itself, so secrets.yml pointing at it changes nothing.
  def test_secrets_yml_reading_secret_key_base_env_passes
    write_config "secrets.yml", "production:\n  secret_key_base: <%= ENV[\"SECRET_KEY_BASE\"] %>\n"

    assert_nil checks(RailsPreflight::ConfigAnalyzer.new(@tmp_dir, "6.1.7", target_rails: "7.2").run).find { |c| c[:removed_in] }
  end

  private

  def write_config(path, content)
    file = File.join(@tmp_dir, "config", path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
  end

  def checks(result)
    result[:checks]
  end

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
