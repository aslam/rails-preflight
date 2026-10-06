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

  def test_scans_migrations_and_rake_tasks
    FileUtils.mkdir_p(File.join(@tmp_dir, "db", "migrate"))
    FileUtils.mkdir_p(File.join(@tmp_dir, "lib", "tasks"))
    File.write(File.join(@tmp_dir, "db", "migrate", "20200101000000_backfill.rb"), "  deprecated_method\n")
    File.write(File.join(@tmp_dir, "lib", "tasks", "backfill.rake"), "  deprecated_method\n")

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, File.join(@db_dir, "deprecations.yml")).run[:checks].first

    assert_equal ["db/migrate/20200101000000_backfill.rb", "lib/tasks/backfill.rake"],
                 check[:details].map { |d| d[:file] }.sort
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
    "erubis_handler" => ["config/initializers/erb.rb", "class Haml::Erubis < ActionView::Template::Handlers::Erubis"],
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
    "enqueue_after_transaction_commit" => ["config/initializers/jobs.rb", "config.active_job.enqueue_after_transaction_commit = :always"],
    "migrator_schema_migrations_table_name" => ["lib/tasks/schema.rake", "  puts ActiveRecord::Migrator.schema_migrations_table_name"],
    "supports_migrations" => ["lib/legacy_adapter.rb", "  return unless connection.supports_migrations?"],
    "migrator_migrations_path" => ["config/initializers/migrations.rb", "ActiveRecord::Migrator.migrations_path = 'db/migrate_old'"],
    "add_foreign_key_deferrable_true" => ["db/migrate/20200102000000_add_fk.rb", "    add_foreign_key :orders, :users, deferrable: true"],
    "schema_cache_env" => ["config/initializers/cache.rb", "ENV['SCHEMA_CACHE'] = 'tmp/schema_cache.yml'"],
    "unsigned_float_decimal" => ["db/migrate/20200101000000_add_rate.rb", "      t.unsigned_decimal :rate, precision: 10"],
    "render_text_nothing" => ["app/controllers/health_controller.rb", "    render text: 'OK'"],
    "controller_filters" => ["app/controllers/application_controller.rb", "  before_filter :authenticate_user!"],
    "serve_static_files" => ["config/environments/staging.rb", "  config.serve_static_files = ENV['RAILS_SERVE_STATIC_FILES'].present?"],
    "raise_in_transactional_callbacks" => ["config/initializers/transactions.rb", "    config.active_record.raise_in_transactional_callbacks = true"],
    "use_transactional_fixtures" => ["test/support/transactions.rb", "  self.use_transactional_fixtures = true"],
    "module_parent" => ["config/initializers/session_store.rb", 'Rails.application.config.session_store :cookie_store, key: "_#{Rails.application.class.parent_name.underscore}_session"'],
    "represent_boolean_as_integer" => ["config/initializers/sqlite.rb", "    config.active_record.sqlite3.represent_boolean_as_integer = true"],
    "active_storage_queue" => ["config/environments/production.rb", "  config.active_storage.queue = :low_priority"],
    "logger_silence_constant" => ["lib/quiet_logger.rb", "  include LoggerSilence"],
    "connection_config" => ["lib/tasks/backup.rake", "  db = ActiveRecord::Base.connection_config[:database]"],
    "arel_attribute" => ["app/models/article.rb", "  scope :recent, -> { order(arel_attribute(:created_at).desc) }"],
    "connected_to_database" => ["app/models/report.rb", "  ActiveRecord::Base.connected_to(database: :reporting) { run }"],
    "db_structure_tasks" => ["lib/tasks/ci.rake", "  Rake::Task['db:structure:dump'].invoke"],
    "use_sha1_digests" => ["config/initializers/new_framework_defaults_6_1.rb", "Rails.application.config.active_support.use_sha1_digests = true"],
    "uri_parser" => ["lib/link_checker.rb", "  uri = URI.parser.parse(url)"],
    "action_view_raise_on_missing_translations" => ["config/environments/test.rb", "  config.action_view.raise_on_missing_translations = true"],
    "hosts_response_app" => ["config/initializers/hosts.rb", "    config.action_dispatch.hosts_response_app = ->(env) { [403, {}, ['Blocked']] }"],
    "to_s_format" => ["app/views/orders/show.html.erb", "<%= order.created_at.to_s(:long) %>"],
    "system_test_poltergeist_webkit" => ["test/application_system_test_case.rb", "  driven_by :poltergeist"],
    "active_storage_current_host" => ["app/controllers/concerns/storage_host.rb", "    ActiveStorage::Current.host = request.base_url"],
    "configs_for_include_replicas" => ["lib/tasks/replicas.rake", "  ActiveRecord::Base.configurations.configs_for(env_name: 'production', include_replicas: true)"],
    "commit_transaction_on_non_local_return" => ["config/initializers/new_framework_defaults_7_1.rb", "Rails.application.config.active_record.commit_transaction_on_non_local_return = true"],
    "allow_deprecated_singular_associations_name" => ["config/initializers/associations.rb", "Rails.application.config.active_record.allow_deprecated_singular_associations_name = false"],
    "warn_on_records_fetched_greater_than" => ["config/environments/development.rb", "  config.active_record.warn_on_records_fetched_greater_than = 1000"],
    "sqlite3_deprecated_warning" => ["config/initializers/sqlite_warning.rb", "Rails.application.config.active_record.sqlite3_deprecated_warning = false"],
    "connection_pool_connection" => ["lib/health_check.rb", "  ActiveRecord::Base.connection_pool.connection.execute('SELECT 1')"],
    "allow_deprecated_parameters_hash_equality" => ["config/initializers/new_framework_defaults_7_2.rb", "Rails.application.config.action_controller.allow_deprecated_parameters_hash_equality = false"],
    "use_big_decimal_serializer" => ["config/initializers/new_framework_defaults_7_0.rb", "Rails.application.config.active_job.use_big_decimal_serializer = true"],
    "rails_console_methods" => ["lib/console_helpers.rb", "Rails::ConsoleMethods.include(ConsoleHelpers)"],
    "form_with_model_nil" => ["app/views/searches/new.html.erb", "<%= form_with url: search_path, model: nil do |f| %>"],
    "route_multiple_paths" => ["config/routes.rb", "  get ['/about', '/about-us'], to: 'pages#about'"],
    "qu_queue_adapter" => ["config/initializers/active_job.rb", "config.active_job.queue_adapter = :qu"],
    "http_parameter_filter" => ["app/controllers/concerns/log_params.rb", "filter = ActionDispatch::Http::ParameterFilter.new([:password])"],
    "mailer_receive" => ["lib/tasks/inbox.rake", "  InboxMailer.receive(STDIN.read)"],
    "active_storage_downloading" => ["app/models/upload.rb", "  include ActiveStorage::Downloading"],
    "variant_combine_options" => ["app/views/users/_avatar.html.erb", "<%= image_tag user.avatar.variant(combine_options: { resize: '100x100' }) %>"]
  }.freeze

  # The replacement APIs. Flagging code that is already fixed is worse than missing it.
  NEAR_MISSES = [
    "user.update(name: 'x')",
    "get :show, params: { id: 1 }",
    "get :index, :format => \"json\"",
    "post :create, :params => { name: 'x' }",
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
    "class Wrapper < BasicObject",
    "add_foreign_key :orders, :users, deferrable: :deferred",
    "t.decimal :rate, precision: 10, scale: 2",
    "puts ActiveRecord::SchemaMigration.table_name",
    "render plain: 'OK'",
    "head :no_content",
    "before_action :authenticate_user!",
    "skip_before_action :verify_authenticity_token",
    "config.public_file_server.enabled = true",
    "self.use_transactional_tests = true",
    "key = Rails.application.class.module_parent_name.underscore",
    "config.active_storage.queues.analysis = :low_priority",
    "include ActiveSupport::LoggerSilence",
    "db = ActiveRecord::Base.connection_db_config.database",
    "order(arel_table[:created_at].desc)",
    "ActiveRecord::Base.connected_to(role: :reading) { run }",
    "Rake::Task['db:schema:dump'].invoke",
    "config.active_support.hash_digest_class = OpenSSL::Digest::SHA1",
    "uri = URI::DEFAULT_PARSER.parse(url)",
    "config.i18n.raise_on_missing_translations = true",
    "self.enqueue_after_transaction_commit = false",
    "<%= order.created_at.to_fs(:long) %>",
    "id.to_s",
    "hex = 255.to_s(16)",
    "driven_by :selenium, using: :headless_chrome",
    "ActiveStorage::Current.url_options = { host: request.base_url }",
    "configs_for(env_name: 'production', include_hidden: true)",
    "config.active_job.queue_adapter = :queue_classic",
    "filter = ActiveSupport::ParameterFilter.new([:password])",
    "UserMailer.welcome(user).deliver_later",
    "<%= image_tag user.avatar.variant(resize_to_limit: [100, 100]) %>",
    "ActiveRecord::Base.connection_pool.with_connection { |conn| conn.execute('SELECT 1') }",
    "<%= form_with url: search_path do |f| %>",
    "get '/about', to: 'pages#about'",
    "class MyErb < ActionView::Template::Handlers::ERB::Erubi"
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
