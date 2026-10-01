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

  # One line per shipped rule. A new rule without a sample here fails the test below,
  # which is the point: every pattern has to prove it matches something real.
  SHIPPED_HITS = {
    "update_attributes" => ["app/models/user.rb", "user.update_attributes(name: 'x')"],
    "controller_test_positional_params" => ["test/users_controller_test.rb", "get :show, id: 1"],
    "application_secrets" => ["config/initializers/auth.rb", "KEY = Rails.application.secrets.api_key"],
    "controller_force_ssl" => ["app/controllers/billing_controller.rb", "  force_ssl if: :production?"],
    "actionmailer_delivery_job" => ["app/mailers/user_mailer.rb", "self.delivery_job = ActionMailer::DeliveryJob"],
    "allow_unsafe_raw_sql" => ["config/initializers/sql.rb", "ActiveRecord::Base.allow_unsafe_raw_sql = :disabled"],
    "legacy_connection_handling" => ["config/application.rb", "config.active_record.legacy_connection_handling = false"],
    "active_record_partial_writes" => ["config/initializers/writes.rb", "config.active_record.partial_writes = false"],
    "per_thread_registry" => ["lib/current_tenant.rb", "  extend ActiveSupport::PerThreadRegistry"],
    "clear_connections" => ["lib/forking_worker.rb", "ActiveRecord::Base.clear_active_connections!"],
    "migration_check_pending" => ["test/test_helper.rb", "ActiveRecord::Migration.check_pending!"],
    "fixture_path_assignment" => ["test/fixtures_helper.rb", "self.fixture_path = File.expand_path('fixtures', __dir__)"],
    "halt_callback_chains_on_return_false" => ["config/initializers/callbacks.rb", "ActiveSupport.halt_callback_chains_on_return_false = false"],
    "string_callback_conditions" => ["app/models/post.rb", '  before_save :normalize, if: "draft?"'],
    "params_parser_parse_error" => ["app/controllers/api_controller.rb", "  rescue ActionController::ParamsParser::ParseError"],
    "secret_token" => ["config/initializers/secret_token.rb", "Example::Application.config.secret_token = 'abc'"],
    "image_alt_helper" => ["app/views/posts/show.html.erb", "<%= image_alt('logo.png') %>"],
    "record_tag_helper" => ["app/views/posts/index.html.erb", "<%= div_for(post) do %>"],
    "fragment_cache_key" => ["app/controllers/posts_controller.rb", "  key = fragment_cache_key(['posts', post])"],
    "test_response_success" => ["test/integration/posts_test.rb", "  assert response.success?"],
    "enum_keyword_arguments" => ["app/models/order.rb", "  enum status: { pending: 0, shipped: 1 }"],
    "proxy_object" => ["lib/wrapper.rb", "class Wrapper < ActiveSupport::ProxyObject"],
    "read_encrypted_secrets" => ["config/initializers/encrypted.rb", "config.read_encrypted_secrets = true"],
    "stats_directories" => ["lib/stats.rb", "STATS_DIRECTORIES << ['Services', 'app/services']"],
    "benchmark_ms" => ["lib/profiler.rb", "  elapsed = Benchmark.ms { work }"],
    "enqueue_after_transaction_commit" => ["config/initializers/jobs.rb", "config.active_job.enqueue_after_transaction_commit = :always"]
  }.freeze

  # The replacement APIs. Flagging code that is already fixed is worse than missing it.
  NEAR_MISSES = [
    "user.update(name: 'x')",
    "get :show, params: { id: 1 }",
    "Rails.application.credentials.api_key",
    "config.force_ssl = true",
    "self.delivery_job = ActionMailer::MailDeliveryJob",
    "config.active_record.partial_inserts = false",
    "config.active_record.partial_updates = false",
    "ActiveRecord::Base.connection_handler.clear_active_connections!",
    "ActiveRecord::Migration.check_all_pending!",
    "self.fixture_paths = [File.expand_path('fixtures', __dir__)]",
    "before_save :normalize, if: :draft?",
    "before_save :normalize, if: -> { draft? }",
    "rescue ActionDispatch::Http::Parameters::ParseError",
    "config.secret_key_base = ENV['SECRET_KEY_BASE']",
    "key = combined_fragment_cache_key(['posts', post])",
    "assert response.successful?",
    "enum :status, { pending: 0, shipped: 1 }",
    "class Wrapper < BasicObject"
  ].freeze

  def test_every_shipped_rule_matches_its_canonical_snippet
    SHIPPED_HITS.each_value { |path, line| write_app_file(path, line) }

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, target_rails: "8.0", current_rails: "5.2.0").run[:checks]

    shipped_rules.each do |rule|
      sample_path, = SHIPPED_HITS.fetch(rule["id"]) { flunk "rule #{rule['id']} has no sample in SHIPPED_HITS" }
      check = checks.find { |c| c[:message] == rule["message"] }

      refute_nil check, "rule #{rule['id']} did not match its sample line"
      assert_includes check[:details].map { |d| d[:file] }, sample_path, "rule #{rule['id']} missed #{sample_path}"
    end
  end

  def test_replacement_apis_are_not_flagged
    NEAR_MISSES.each_with_index do |line, i|
      # Both an app and a test path, so directory-scoped rules get their chance to misfire.
      write_app_file("app/models/fixed_#{i}.rb", line)
      write_app_file("test/fixed_#{i}_test.rb", line)
    end

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, target_rails: "8.0", current_rails: "5.2.0").run[:checks]
    flagged = checks.flat_map { |c| (c[:details] || []).map { |d| "#{d[:file]}: #{d[:snippet]}" } }

    assert_empty flagged
  end

  private

  def shipped_rules
    YAML.load_file(File.expand_path("../database/deprecations.yml", __dir__))["deprecations"]
  end

  def write_app_file(relative_path, line)
    full = File.join(@tmp_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, "#{line}\n")
  end
end
