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
    assert_equal "test_rule", check[:rule]
    assert_equal :high, check[:confidence]
    assert_equal "7.0", check[:removed_in]
    assert_equal "http://example.com", check[:source]
    assert_equal [{ file: "app/model.rb", line: 2, snippet: "deprecated_method", test: false }], check[:files]
  end

  def test_removed_api_blocks_targets_at_or_past_removal
    File.write(File.join(@app_dir, "model.rb"), "deprecated_method\n")
    db = File.join(@db_dir, "deprecations.yml")

    assert_equal :failed, RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, db, target_rails: "7.0").run[:checks].first[:status]
    assert_equal :warning, RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, db, target_rails: "6.1").run[:checks].first[:status]
  end

  def test_api_already_removed_in_current_version_is_already_broken
    File.write(File.join(@app_dir, "model.rb"), "deprecated_method\n")
    db = File.join(@db_dir, "deprecations.yml")

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, db, target_rails: "7.1", current_rails: "7.0.4").run[:checks].first

    assert_equal :broken, check[:kind]
    assert_equal "7.0", check[:removed_in]
    assert_nil RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, db, target_rails: "7.1", current_rails: "6.1.7").run[:checks].first[:kind]
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

    assert_equal 2, check[:files].size
    assert_equal ["app/views/users/index.html.erb", "config/application.rb"], check[:files].map { |d| d[:file] }.sort
  end

  def test_scans_haml_and_slim_but_not_their_silent_comments
    write_app_file("app/views/users/index.html.haml", <<~HAML)
      #main= deprecated_method
      -# deprecated_method
      -#
        = deprecated_method
      / deprecated_method in an HTML comment
      /
        = deprecated_method
    HAML
    write_app_file("app/views/users/show.html.slim", <<~SLIM)
      / deprecated_method
        = deprecated_method
      p = deprecated_method
      /! deprecated_method in an HTML comment
        = deprecated_method
    SLIM

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, File.join(@db_dir, "deprecations.yml")).run[:checks].first

    assert_equal ["app/views/users/index.html.haml:1", "app/views/users/index.html.haml:7", "app/views/users/show.html.slim:3", "app/views/users/show.html.slim:5"],
                 check[:files].map { |d| "#{d[:file]}:#{d[:line]}" }.sort
  end

  def test_gem_that_keeps_the_api_skips_the_rule
    write_app_file("app/views/posts/index.html.erb", "<%= div_for(post) do %>")
    checks = -> { RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, current_rails: "5.2.8").run[:checks] }

    assert_equal :broken, checks.call.find { |c| c[:rule] == "record_tag_helper" }[:kind]

    write_app_file("Gemfile.lock", "GEM\n  specs:\n    record_tag_helper (1.0.1)\n      actionview (>= 5)\n")
    assert_nil checks.call.find { |c| c[:rule] == "record_tag_helper" }
  end

  def test_scans_migrations_and_rake_tasks
    FileUtils.mkdir_p(File.join(@tmp_dir, "db", "migrate"))
    FileUtils.mkdir_p(File.join(@tmp_dir, "lib", "tasks"))
    File.write(File.join(@tmp_dir, "db", "migrate", "20200101000000_backfill.rb"), "  deprecated_method\n")
    File.write(File.join(@tmp_dir, "lib", "tasks", "backfill.rake"), "  deprecated_method\n")

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, File.join(@db_dir, "deprecations.yml")).run[:checks].first

    assert_equal ["db/migrate/20200101000000_backfill.rb", "lib/tasks/backfill.rake"],
                 check[:files].map { |d| d[:file] }.sort
  end

  def test_path_scoped_rule_skips_directories_it_does_not_apply_to
    FileUtils.mkdir_p(File.join(@tmp_dir, "config"))
    File.write(File.join(@tmp_dir, "config", "routes.rb"), "get :show, on: :member\n")

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir).run[:checks]

    assert_nil checks.find { |c| c[:message].include?("positionally") }
  end

  def test_bare_errors_in_helpers_and_views_is_a_local
    write_app_file("app/helpers/settings_helper.rb", "    errors.each do |name, message|\n    form.errors.each do |attribute, message|\n")
    write_app_file("app/views/shared/_errors.html.erb", "<% errors[:base] << 'x' %>\n")
    write_app_file("lib/sudo_form.rb", "    errors.each do |attribute, message|\n")

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir).run[:checks]
    check = checks.find { |c| c[:message].start_with?("Enumerating 'ActiveModel::Errors'") }

    assert_equal ["app/helpers/settings_helper.rb:2", "lib/sudo_form.rb:1"], check[:files].map { |d| "#{d[:file]}:#{d[:line]}" }.sort
    assert_nil checks.find { |c| c[:message].start_with?("Changing error messages") }
  end

  def test_bare_errors_is_a_local_where_the_file_assigns_or_takes_it
    write_app_file("lib/json_error.rb", "    errors = create_errors_array obj\n    errors[:type] = opts[:type]\n")
    write_app_file("lib/onebox_check.rb", "  def check(errors = {})\n    errors[:url] << 'is blank'\n")
    write_app_file("lib/collect.rb", "  list.each do |item, errors|\n    errors[:url] << 'is blank'\n")
    write_app_file("lib/post_creator.rb", "    valid = a || errors.any? || b\n    errors[:base] << 'is blank'\n    record.errors[:base] << 'too long'\n")
    write_app_file("app/models/post.rb", "  def valid_body? = errors.empty?\n    errors[:body] << 'is blank'\n  def check_title\n    errors[:title] << 'is blank'\n")

    files = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir).run[:checks].flat_map { |c| (c[:files] || []).map { |d| "#{d[:file]}:#{d[:line]}" } }

    assert_equal ["app/models/post.rb:2", "app/models/post.rb:4", "lib/post_creator.rb:2", "lib/post_creator.rb:3"], files.sort
  end

  def test_snippets_hide_secret_values
    File.write(File.join(@app_dir, "secrets.rb"), <<~RUBY)
      deprecated_method; App.config.secret_token = '189b1a78ff508196'
      deprecated_method(api_key: "sk-live-123", name: "kept")
      deprecated_method password: hunter2
      deprecated_method SECRET_KEY_BASE=abc123 rails s
      deprecated_method Sidekiq::Web.set :session_secret, Rails.configuration.secret_token
      deprecated_method(name: "kept")
    RUBY

    snippets = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, File.join(@db_dir, "deprecations.yml")).run[:checks].first[:files].map { |d| d[:snippet] }

    assert_equal [
      "deprecated_method; App.config.secret_token = '[hidden]'",
      'deprecated_method(api_key: "[hidden]", name: "[hidden]")',
      "deprecated_method password: [hidden]",
      "deprecated_method SECRET_KEY_BASE=[hidden]",
      "deprecated_method Sidekiq::Web.set :session_secret, Rails.configuration.secret_token",
      'deprecated_method(name: "kept")'
    ], snippets
  end

  def test_shipped_rule_flags_application_secrets_in_config
    FileUtils.mkdir_p(File.join(@tmp_dir, "config", "initializers"))
    File.write(File.join(@tmp_dir, "config", "initializers", "auth.rb"), "KEY = Rails.application.secrets.api_key\n")

    check = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, target_rails: "7.2", current_rails: "7.1.3").run[:checks]
                                               .find { |c| c[:message].include?("Rails.application.secrets") }

    assert_equal :failed, check[:status]
    assert_equal "config/initializers/auth.rb", check[:files].first[:file]
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

    assert_equal 2, check[:files].size
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
    "return_only_media_type_on_content_type" => ["config/initializers/new_framework_defaults_6_0.rb", "Rails.application.config.action_dispatch.return_only_media_type_on_content_type = false"],
    "return_false_on_aborted_enqueue" => ["config/initializers/active_job_defaults.rb", "Rails.application.config.active_job.return_false_on_aborted_enqueue = true"],
    "active_record_base_config_accessors" => ["config/initializers/time_zone.rb", "ActiveRecord::Base.default_timezone = :local"],
    "trusted_proxies_single_value" => ["config/environments/proxy.rb", "  config.action_dispatch.trusted_proxies = IPAddr.new('10.0.0.0/8')"],
    "removed_core_ext_files" => ["lib/core_ext.rb", "require 'active_support/core_ext/uri'"],
    "schema_file_type" => ["lib/tasks/schema_dump.rake", "  file = ActiveRecord::Tasks::DatabaseTasks.schema_file_type(:sql)"],
    "static_cache_control" => ["config/environments/cdn.rb", "  config.static_cache_control = 'public, max-age=3600'"],
    "length_validator_tokenizer" => ["app/models/essay.rb", "  validates :body, length: { maximum: 300, tokenizer: ->(str) { str.split } }"],
    "original_exception" => ["app/controllers/errors_controller.rb", "    cause = exception.original_exception"],
    "delete_destroy_all_conditions" => ["app/models/session_cleaner.rb", "    Session.delete_all(['updated_at < ?', 1.week.ago])"],
    "errors_get_set" => ["app/models/legacy_form.rb", "    errors[:password] = errors[:password] + errors[:password_confirmation]"],
    "dispatch_callbacks_to_prepare" => ["config/initializers/reload_hooks.rb", "ActionDispatch::Callbacks.to_prepare { Plugin.reload! }"],
    "concurrency_latch" => ["lib/worker_pool.rb", "  latch = ActiveSupport::Concurrency::Latch.new(3)"],
    "error_on_ignored_order_or_limit" => ["config/initializers/batches.rb", "ActiveRecord::Base.error_on_ignored_order_or_limit = true"],
    "association_class_name_constant" => ["app/models/purchase.rb", "  belongs_to :buyer, class_name: User"],
    "cache_key_timestamp_name" => ["app/views/posts/_post.html.erb", "<% cache post.cache_key(:published_at) do %>"],
    "removed_core_ext_files_6_1" => ["lib/extensions.rb", "require 'active_support/core_ext/hash/compact'"],
    "render_file_relative_path" => ["app/controllers/pages_controller.rb", "    render :file => 'layouts/base'"],
    "mb_chars_normalize" => ["app/models/slug.rb", "    name.mb_chars.normalize(:kd).to_s"],
    "errors_hash_methods" => ["app/controllers/api/base_controller.rb", "    render json: { fields: record.errors.keys }"],
    "errors_messages_mutation" => ["app/models/invite.rb", "    errors[:email] << 'is taken'"],
    "errors_each_two_args" => ["app/helpers/form_errors_helper.rb", "    model.errors.each do |attribute, message|"],
    "configurations_to_h" => ["lib/tasks/db_info.rake", "  puts ActiveRecord::Base.configurations.to_h.keys"],
    "db_config_spec_name" => ["lib/shard_router.rb", "  name = db_config.spec_name"],
    "database_tasks_removed_methods" => ["lib/tasks/schema_backup.rake", "  path = ActiveRecord::Tasks::DatabaseTasks.dump_filename('primary')"],
    "mailgun_api_key" => ["config/initializers/mailbox.rb", "ENV.fetch('MAILGUN_INGRESS_API_KEY')"],
    "retry_on_exponentially_longer" => ["app/jobs/sync_job.rb", "  retry_on Timeout::Error, wait: :exponentially_longer, attempts: 5"],
    "cache_store_pool_size" => ["config/environments/cache.rb", "  config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'], pool_size: 5, pool_timeout: 5 }"],
    "mem_cache_store_dalli_client" => ["config/environments/memcache.rb", "  config.cache_store = :mem_cache_store, Dalli::Client.new('localhost:11211')"],
    "to_default_s" => ["app/models/period_report.rb", "    period.to_default_s"],
    "mailer_preview_path" => ["config/environments/previews.rb", "  config.action_mailer.preview_path = Rails.root.join('spec/mailers/previews')"],
    "removed_7_2_framework_settings" => ["config/initializers/to_s_conversion.rb", "Rails.application.config.active_support.disable_to_s_conversion = true"],
    "cache_format_version_6_1" => ["config/initializers/cache_format.rb", "Rails.application.config.active_support.cache_format_version = 6.1"],
    "show_exceptions_boolean" => ["config/environments/ci.rb", "  config.action_dispatch.show_exceptions = false"],
    "serialize_class_argument" => ["app/models/setting.rb", "  serialize :preferences, JSON"],
    "deprecation_singleton" => ["lib/legacy_api.rb", "    ActiveSupport::Deprecation.warn('LegacyApi#fetch is deprecated')"],
    "merge_rewhere" => ["app/models/scopes/visible.rb", "    relation.merge(Post.where(status: 'live'), rewhere: true)"],
    "assert_enqueued_email_with_args" => ["test/mailers/welcome_test.rb", "    assert_enqueued_email_with UserMailer, :welcome, args: { user: user }"],
    "permissions_policy_removed_directives" => ["config/initializers/permissions_policy.rb", "  policy.vibrate :none"],
    "rails_console_requires_8_0" => ["lib/console_tools.rb", "require 'rails/console/helpers'"],
    "rails_console_methods_require" => ["lib/console_extensions.rb", "require \"rails/console/methods\""],
    "sucker_punch_queue_adapter" => ["config/initializers/sucker_punch.rb", "Rails.application.config.active_job.queue_adapter = :sucker_punch"],
    "to_time_preserves_timezone_false" => ["config/initializers/time_compat.rb", "ActiveSupport.to_time_preserves_timezone = false"],
    "rails_update_tasks" => ["script/upgrade.sh", "bundle exec rake rails:update"],
    "rake_routes_notes_tasks" => [".github/workflows/ci.yml", "      - run: bundle exec rake routes"],
    "rake_stats" => ["Makefile", "\tbin/rake stats"],
    "cable_evented_redis" => ["config/cable.yml", "  adapter: evented_redis"],
    "sqlite3_retries" => ["config/database.yml", "  retries: 1000"],
    "azure_storage_service" => ["config/storage.yml", "  service: AzureStorage"],
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
    "expect(ActiveRecord::Base.connection_handler).to receive(:clear_active_connections!)",
    "AhoyEmail.secret_token = Rails.application.secret_key_base",
    'render file: "public/404.html", status: :not_found',
    "if config.active_record.respond_to?(:warn_on_records_fetched_greater_than=)",
    "if config.action_controller.respond_to?(:allow_deprecated_parameters_hash_equality)",
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
    "system('bin/rails routes')",
    "system('bin/rails app:update')",
    "system('bin/rails stats')",
    "system('bundle exec rake db:schema:load')",
    "config.active_job.queue_adapter = :async",
    "config.active_support.to_time_preserves_timezone = :zone",
    "retry_on Timeout::Error, wait: :polynomially_longer, attempts: 5",
    "config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'], pool: { size: 5, timeout: 5 } }",
    "config.cache_store = :mem_cache_store, 'localhost:11211'",
    "config.action_mailer.preview_paths << Rails.root.join('spec/mailers/previews').to_s",
    "config.active_support.cache_format_version = 7.1",
    "config.action_dispatch.show_exceptions = :none",
    "serialize :preferences, coder: JSON",
    "serialize :preferences, type: Hash, coder: YAML",
    "deprecator = ActiveSupport::Deprecation.new('2.0', 'LegacyApi')",
    "relation.merge(Post.where(status: 'live'))",
    "assert_enqueued_email_with UserMailer, :welcome, params: { user: user }",
    "assert_enqueued_email_with UserMailer, :welcome, args: [ @user ] do",
    "policy.camera :none",
    "config.public_file_server.headers = { 'Cache-Control' => 'public, max-age=3600' }",
    "raise e.cause if e.cause",
    "Session.where('updated_at < ?', 1.week.ago).delete_all",
    "destroy_all(@account.subscriptions)",
    "update_attributes = { name: 'Jimmy' }",
    "expect(attrs).to eq(update_attributes)",
    "updater.update(update_attributes)",
    "tokenizer: 'standard',",
    ":tokenizer => 'edge_ngram',",
    "image_description: image_alt || '',",
    "image_alt: eq('A good boy'),",
    "Session.delete_all",
    "user.posts.delete_all(:delete_all)",
    "errors.add(:name, :blank)",
    "ActiveSupport::Reloader.to_prepare { Plugin.reload! }",
    "latch = Concurrent::CountDownLatch.new(3)",
    "config.active_record.error_on_ignored_order = true",
    "belongs_to :buyer, class_name: 'User'",
    "belongs_to :buyer, class_name: \"Admin::User\"",
    "policy :not_silenced_already, class_name: User::Policy::NotAlreadySilenced",
    "<% cache post do %>",
    "require 'active_support/core_ext/hash/indifferent_access'",
    "render file: Rails.root.join('public/maintenance.html')",
    'render file: "#{Rails.root}/public/404.html", status: 404',
    "name.unicode_normalize(:nfkd)",
    "render json: { fields: record.errors.attribute_names }",
    "errors.add(:email, :taken)",
    "model.errors.each do |error|",
    "@errors.each do |key, value|",
    "@errors.keys.first",
    "@errors[:base] = 'gateway down'",
    "if errors[:email].any?",
    "errors[key] = validator.errors.full_messages",
    "if errors.messages[:email] == ['is taken']",
    "ActiveRecord::Base.configurations.configs_for(env_name: 'production')",
    "name = db_config.name",
    "path = ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(db_config)",
    "ENV.fetch('MAILGUN_INGRESS_SIGNING_KEY')",
    "ActiveRecord.default_timezone = :local",
    "config.active_record.default_timezone = :local",
    "config.action_dispatch.trusted_proxies = [IPAddr.new('10.0.0.0/8')]",
    "require 'active_support/core_ext/uri/escape'",
    "filter = ActiveSupport::ParameterFilter.new([:password])",
    "UserMailer.welcome(user).deliver_later",
    "<%= image_tag user.avatar.variant(resize_to_limit: [100, 100]) %>",
    "ActiveRecord::Base.connection_pool.with_connection { |conn| conn.execute('SELECT 1') }",
    "<%= form_with url: search_path do |f| %>",
    "get '/about', to: 'pages#about'",
    "class MyErb < ActionView::Template::Handlers::ERB::Erubi"
  ].freeze

  def test_every_shipped_rule_matches_its_canonical_snippet
    paths = SHIPPED_HITS.values.map(&:first)
    assert_equal [], paths.select { |path| paths.count(path) > 1 }.uniq, "samples sharing a path overwrite each other"
    SHIPPED_HITS.each_value { |path, line| write_app_file(path, line) }

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, target_rails: "8.0", current_rails: "5.2.0").run[:checks]

    shipped_rules.each do |rule|
      sample_path, = SHIPPED_HITS.fetch(rule["id"]) { flunk "rule #{rule['id']} has no sample in SHIPPED_HITS" }
      check = checks.find { |c| c[:message] == rule["message"] }

      refute_nil check, "rule #{rule['id']} did not match its sample line"
      assert_includes check[:files].map { |d| d[:file] }, sample_path, "rule #{rule['id']} missed #{sample_path}"
    end
  end

  def test_scripts_and_ci_config_get_only_task_rules
    write_app_file("bin/setup", "user.update_attributes(name: 'x')\nsystem! 'bin/rake db:structure:load'")
    write_app_file("Procfile", "release: bundle exec rake db:structure:load")

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, target_rails: "7.0", current_rails: "6.1.7").run[:checks]
    flagged = checks.flat_map { |c| (c[:files] || []).map { |d| d[:file] } }

    assert_equal %w[Procfile bin/setup], flagged.sort
    assert_equal 1, checks.count { |c| c[:files].is_a?(Array) }
  end

  def test_yaml_rules_run_only_on_their_config_files
    write_app_file("config/cable.yml", "production:\n  adapter: redis\n  url: <%= ENV['REDIS_URL'] %>")
    write_app_file("config/database.yml", "default: &default\n  adapter: sqlite3\n  timeout: 5000")
    write_app_file("config/storage.yml", "amazon:\n  service: S3\n  # service: AzureStorage")
    write_app_file("config/sidekiq.yml", ":retries: 3\nretries: 3")
    write_app_file("app/models/socket_config.rb", "ADAPTER = { adapter: evented_redis }")

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, target_rails: "8.1", current_rails: "5.1.7").run[:checks]

    assert_equal [], checks.flat_map { |c| (c[:files] || []).map { |d| "#{d[:file]}: #{d[:snippet]}" } }
  end

  def test_replacement_apis_are_not_flagged
    NEAR_MISSES.each_with_index do |line, i|
      # Both an app and a test path, so directory-scoped rules get their chance to misfire.
      write_app_file("app/models/fixed_#{i}.rb", line)
      write_app_file("test/fixed_#{i}_test.rb", line)
    end

    checks = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, target_rails: "8.0", current_rails: "5.2.0").run[:checks]
    flagged = checks.flat_map { |c| (c[:files] || []).map { |d| "#{d[:file]}: #{d[:snippet]}" } }

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
