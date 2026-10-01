require "minitest/autorun"
require "yaml"
require "tmpdir"
require "fileutils"
require_relative "../lib/rails_preflight/deprecation_analyzer"

class DeprecationAnalyzerTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    # Create fake deprecations.yml
    @db_dir = File.join(@tmp_dir, "database")
    FileUtils.mkdir_p(@db_dir)
    
    yaml_content = {
      "deprecations" => [
        {
          "id" => "test_rule",
          "pattern" => "deprecated_method",
          "message" => "Don't use this",
          "confidence" => "High",
          "guide_link" => "http://example.com",
          "recategorization" => "Rails 6.0 -> 6.1",
          "removed_in" => "7.0"
        }
      ]
    }.to_yaml
    
    File.write(File.join(@db_dir, "deprecations.yml"), yaml_content)
    
    # Create fake app code
    @app_dir = File.join(@tmp_dir, "app")
    FileUtils.mkdir_p(@app_dir)
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def test_detects_and_structures_deprecation
    File.write(File.join(@app_dir, "model.rb"), "def foo\n  deprecated_method\nend")
    File.write(File.join(@app_dir, "user.rb"), "User.update_attributes(name: 'foo')")

    analyzer = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, File.join(@db_dir, "deprecations.yml"))
    result = analyzer.run

    assert_equal :warning, result[:status]
    check = result[:checks].first

    assert_equal "Don't use this", check[:message]
    assert_equal true, check[:grouped]
    assert_equal "http://example.com", check[:guide_link]
    assert_equal 1, check.dig(:stats, :occurrences)
    assert_equal 1, check.dig(:stats, :occurrences_app)
    assert_equal 0, check.dig(:stats, :occurrences_test)

    detail = check[:details].first
    assert_equal "High", detail[:confidence]
    assert_equal "http://example.com", detail[:guide_link]
    assert_equal "Rails 6.0 -> 6.1", detail[:recategorization]
    assert_equal "app/model.rb", detail[:file]
    assert_equal 2, detail[:line]
  end

  def test_removed_api_blocks_targets_at_or_past_removal
    File.write(File.join(@app_dir, "model.rb"), "deprecated_method\n")
    db = File.join(@db_dir, "deprecations.yml")

    assert_equal :failed, RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, db, target_rails: "7.0").run[:checks].first[:status]
    assert_equal :warning, RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, db, target_rails: "6.1").run[:checks].first[:status]
  end

  def test_api_already_removed_in_current_version_is_not_a_blocker
    File.write(File.join(@app_dir, "model.rb"), "deprecated_method\n")
    db = File.join(@db_dir, "deprecations.yml")

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, db, target_rails: "7.1", current_rails: "7.0.4").run[:checks].first

    assert_equal :warning, check[:status]
    assert_equal "7.0", check[:removed_in]
    assert_equal :failed, RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, db, target_rails: "7.1", current_rails: "6.1.7").run[:checks].first[:status]
  end

  def test_skips_commented_out_code
    File.write(File.join(@app_dir, "model.rb"), "# deprecated_method was replaced\n  # deprecated_method\n")

    result = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, File.join(@db_dir, "deprecations.yml")).run

    assert_equal :passed, result[:status]
  end

  def test_scans_config_and_erb_templates
    FileUtils.mkdir_p(File.join(@tmp_dir, "config"))
    FileUtils.mkdir_p(File.join(@app_dir, "views", "users"))
    File.write(File.join(@tmp_dir, "config", "application.rb"), "config.x = deprecated_method\n")
    File.write(File.join(@app_dir, "views", "users", "index.html.erb"), "<%= deprecated_method %>\n<%# deprecated_method %>\n")

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, File.join(@db_dir, "deprecations.yml")).run[:checks].first

    assert_equal 2, check.dig(:stats, :occurrences)
    assert_equal ["app/views/users/index.html.erb", "config/application.rb"], check[:details].map { |d| d[:file] }.sort
  end

  def test_path_scoped_rule_skips_directories_it_does_not_apply_to
    FileUtils.mkdir_p(File.join(@tmp_dir, "config"))
    File.write(File.join(@tmp_dir, "config", "routes.rb"), "get :show, on: :member\n")

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir).run[:checks]

    assert_nil checks.find { |c| c[:message].include?("positionally") }
  end

  def test_shipped_rule_flags_application_secrets_in_config
    FileUtils.mkdir_p(File.join(@tmp_dir, "config", "initializers"))
    File.write(File.join(@tmp_dir, "config", "initializers", "auth.rb"), "KEY = Rails.application.secrets.api_key\n")

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, target_rails: "7.2", current_rails: "7.1.3").run[:checks]
                                               .find { |c| c[:message].include?("Rails.application.secrets") }

    assert_equal :failed, check[:status]
    assert_equal "config/initializers/auth.rb", check[:details].first[:file]
  end

  def test_shipped_rule_flags_positional_controller_test_params
    FileUtils.mkdir_p(File.join(@tmp_dir, "test"))
    File.write(File.join(@tmp_dir, "test", "users_controller_test.rb"), <<~RUBY)
      get :show, id: 1
      post :create, :user => { name: "x" }
      get :show, params: { id: 1 }
      post :create, format: :json
      get :index
      get user_url(users(:one))
    RUBY

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir).run[:checks].find { |c| c[:message].include?("positionally") }

    assert_equal 2, check.dig(:stats, :occurrences)
  end
end
