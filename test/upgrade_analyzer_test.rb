require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "net/http"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "rails_preflight"

class UpgradeAnalyzerTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@tmp_dir, "config"))
    File.write(File.join(@tmp_dir, "config", "environment.rb"), "")
    @real_stdout, $stdout = $stdout, StringIO.new # UpgradeAnalyzer#run prints progress
  end

  def teardown
    $stdout = @real_stdout
    FileUtils.remove_entry @tmp_dir
  end

  def test_reads_direct_gems_from_the_lockfile
    File.write(File.join(@tmp_dir, "Gemfile.lock"), <<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          railties (6.1.7)
          sprockets-rails (3.4.2)

      PLATFORMS
        ruby

      DEPENDENCIES
        railties
    LOCKFILE
    FileUtils.mkdir_p(File.join(@tmp_dir, "app/assets"))

    RailsPreflight::UpgradeAnalyzer.new("7.0", @tmp_dir, offline: true).run

    assert_includes report, "Rails 7.0 no longer depends on sprockets-rails, and the Gemfile doesn&#39;t list it."

    File.write(File.join(@tmp_dir, "Gemfile.lock"), File.read(File.join(@tmp_dir, "Gemfile.lock")) + "  sprockets-rails\n")
    RailsPreflight::UpgradeAnalyzer.new("7.0", @tmp_dir, offline: true).run

    refute_includes report, "no longer depends on sprockets-rails"
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

    assert_includes report, "Ruby <b>4.0.1</b> (.ruby-version)"
    assert_includes report, "4.0.1 works"
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

    assert_includes report, "Ruby <b>3.3</b> (.ruby-version)"
  end

  def test_two_part_dockerfile_ruby_tag_does_not_crash
    File.write(File.join(@tmp_dir, "Dockerfile"), "FROM ruby:3.3-slim\n")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Ruby <b>3.3</b> (Dockerfile)"
    assert_includes report, "3.3 works"
  end

  def test_reads_ruby_version_from_gemfile_lock
    write_lockfile(ruby: "3.3.5p100")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Ruby <b>3.3.5</b> (Gemfile.lock)"
    assert_includes report, "3.3.5 works"
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

    assert_includes report, "Rails 7.1.3 <span class=\"to\">to</span> 7.2"
    assert_includes report, "7.1.3 → 7.2"
  end

  def test_flags_target_that_is_not_an_upgrade
    write_lockfile(rails: "7.2.1")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Already on Rails 7.2.1: 7.2 is not an upgrade."
    refute_includes report, "<strong>Rails 7.2.1 → 7.2</strong>" # no upgrade step
  end

  def test_unknown_current_rails_is_reported
    write_lockfile

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Could not read current Rails version from Gemfile.lock."
  end

  def test_refuses_a_directory_that_is_not_a_rails_app
    FileUtils.rm(File.join(@tmp_dir, "config", "environment.rb"))

    error = assert_raises(RailsPreflight::Error) { RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run }

    assert_includes error.message, "doesn't look like a Rails app"
    refute File.exist?(File.join(@tmp_dir, "rails_preflight_report.html"))
  end

  def test_database_rules_apply_to_targets_past_their_version
    FileUtils.mkdir_p(File.join(@tmp_dir, "db"))
    File.write(File.join(@tmp_dir, "db", "schema.rb"), %(create_table "users", id: :integer, charset: "utf8mb3" do |t|\nend\n))

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    assert_includes report, "Legacy utf8mb3 charset detected."
    assert_includes report, "Integer IDs detected."
  end

  def test_path_steps_through_each_minor_version
    write_lockfile(rails: "6.1.7")
    File.write(File.join(@tmp_dir, ".ruby-version"), "2.7.8\n")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    ["6.1.7 → 7.0", "7.0 → 7.1", "7.1 → 7.2", "Needs Ruby 3.1.0–3.4: upgrade Ruby from 2.7.8 to 3.4 first"].each do |text|
      assert_includes report, text
    end
  end

  def test_end_of_life_advice_stays_within_the_target
    write_lockfile(rails: "5.2.8.1")
    File.write(File.join(@tmp_dir, ".ruby-version"), "2.5.9\n")

    RailsPreflight::UpgradeAnalyzer.new("6.0", @tmp_dir).run
    assert_includes report, "Ruby 2.5.9 is end-of-life. Rails 6.0 supports up to Ruby 2.7; Ruby 3.3+ needs Rails 7.1."

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run
    assert_includes report, "Ruby 2.5.9 is end-of-life. Upgrade to Ruby 3.3+."
  end

  def test_defaults_to_the_next_known_minor
    { "5.2.8.1" => "6.0", "7.1.3" => "7.2", "7.2.0" => "8.0" }.each do |current, expected|
      write_lockfile(rails: current)

      RailsPreflight::UpgradeAnalyzer.new(nil, @tmp_dir).run

      assert_includes report, "Rails #{current} <span class=\"to\">to</span> #{expected}"
      assert_includes $stdout.string, "Latest known is 8.1: run `rails-preflight 8.1` for the full path."
    end
  end

  def test_explicit_target_has_no_latest_hint
    write_lockfile(rails: "7.1.3")

    RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run

    refute_includes $stdout.string, "Latest known"
  end

  def test_default_stops_without_a_current_rails
    error = assert_raises(RailsPreflight::Error) { RailsPreflight::UpgradeAnalyzer.new(nil, @tmp_dir).run }
    assert_includes error.message, "No Gemfile.lock in #{@tmp_dir}"

    write_lockfile
    error = assert_raises(RailsPreflight::Error) { RailsPreflight::UpgradeAnalyzer.new(nil, @tmp_dir).run }
    assert_includes error.message, "No Rails in"
    refute File.exist?(File.join(@tmp_dir, "rails_preflight_report.html"))
  end

  def test_default_exits_when_on_the_newest_known_rails
    write_lockfile(rails: "8.1.3")

    RailsPreflight::UpgradeAnalyzer.new(nil, @tmp_dir).run

    assert_includes $stdout.string, "Rails 8.1.3 is already at or past the newest version rails-preflight knows (8.1)."
    refute File.exist?(File.join(@tmp_dir, "rails_preflight_report.html"))
  end

  def test_offline_places_gems_from_the_lockfile_alone
    write_mixed_lockfile

    stub_rubygems(->(_name) { raise "gem check went online" }) do
      RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir, offline: true).run
    end

    assert_includes report, "Private gems (2): compatibility with Rails 7.2 is unknown"
    assert_includes report, "2 gems come from one Gemfile.lock section that lists rubygems.org and https://gems.example.test/; can&#39;t tell which are private with --offline"
  end

  def test_online_looks_up_only_gems_the_lockfile_cannot_place
    write_mixed_lockfile
    looked_up = []

    stub_rubygems(->(name) { looked_up << name; name == "example_sso" ? "404" : "200" }) do
      RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run
    end

    assert_equal %w[devise example_sso], looked_up.sort
    assert_includes report, "Private gems (3): compatibility with Rails 7.2 is unknown"
    assert_includes report, "<b>2</b> gems looked up on rubygems.org"
  end

  def test_gemfile_source_blocks_place_gems_without_going_online
    write_mixed_lockfile
    File.write(File.join(@tmp_dir, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "railties"

      source "https://gems.example.test" do
        if ENV["CI"]
          gem "ci_reporter"
        end
        group :production do
          gem "example_sso" # private fork, though the name is on rubygems.org
        end
      end

      gem "devise"
      gem "acme_auth", source: "https://gems.acme.test"
    GEMFILE

    stub_rubygems(->(_name) { raise "gem check went online" }) do
      RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run
    end

    assert_includes report, "Private gems (3): compatibility with Rails 7.2 is unknown"
    assert_match(/class="names">[^<]*example_sso/, report)
    refute_match(/class="names">[^<]*devise/, report)
    refute_includes report, "Looked up"
  end

  def test_gemfile_sources_split_across_lines_set_from_code_or_in_another_file
    write_mixed_lockfile
    File.write(File.join(@tmp_dir, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "railties"
      gem "devise",
        require: false
      gem "acme_auth",
        source: "https://gems.acme.test"
      eval_gemfile "Gemfile.private"
    GEMFILE
    File.write(File.join(@tmp_dir, "Gemfile.private"), <<~GEMFILE)
      source ENV.fetch("PRIVATE_GEMS") do
        gem "example_sso"
      end
    GEMFILE

    stub_rubygems(->(_name) { raise "gem check went online" }) do
      RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run
    end

    assert_includes report, "Private gems (3): compatibility with Rails 7.2 is unknown"
    assert_match(/class="names">[^<]*example_sso/, report)
    refute_match(/class="names">[^<]*devise/, report)
  end

  def test_online_looks_up_release_dates_for_public_rails_gems_only
    File.write(File.join(@tmp_dir, "Gemfile.lock"), <<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          acts_as_list (0.9.19)
            activerecord (>= 4.2)
          rack (2.2.8)
          railties (6.1.7)

      GEM
        remote: https://gems.acme.test/
        specs:
          acme_auth (2.0.0)
            railties (>= 5.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        acme_auth!
        acts_as_list
        railties
    LOCKFILE
    looked_up = []

    stub_rubygems(->(name) { looked_up << name; ["200", %({"version_created_at": "2019-03-01T10:00:00.000Z"})] }) do
      RailsPreflight::UpgradeAnalyzer.new("7.0", @tmp_dir).run
    end

    assert_equal %w[acts_as_list], looked_up
    assert_includes report, "acts_as_list (last release 2019-03-01)"
  end

  def test_online_lookup_failures_are_reported_as_unchecked
    write_mixed_lockfile

    stub_rubygems(->(name) { name == "devise" ? raise(Net::OpenTimeout, "timed out") : "429" }) do
      RailsPreflight::UpgradeAnalyzer.new("7.2", @tmp_dir).run
    end

    assert_includes report, "Could not verify 2 gems against rubygems.org"
    assert_includes report, "devise (Net::OpenTimeout: timed out)"
    assert_includes report, "example_sso (RuntimeError: HTTP 429)"
  end

  private

  def report
    File.read(File.join(@tmp_dir, "rails_preflight_report.html"))
  end

  # rubygems.org stand-in: respond.(gem_name) returns a status code or raises.
  def stub_rubygems(respond)
    http = Object.new
    http.define_singleton_method(:request) do |req|
      code, body = respond.(req.path[%r{/gems/(.+)\.json}, 1])
      Struct.new(:code, :body).new(code, body || "{}")
    end
    Net::HTTP.singleton_class.alias_method(:real_start, :start)
    Net::HTTP.define_singleton_method(:start) { |*, &block| block.(http) }
    yield
  ensure
    Net::HTTP.singleton_class.remove_method(:start)
    Net::HTTP.singleton_class.alias_method(:start, :real_start)
  end

  # One gem per kind of source: git, rubygems.org, private registry only, and a section mixing both.
  def write_mixed_lockfile
    File.write(File.join(@tmp_dir, "Gemfile.lock"), <<~LOCKFILE)
      GIT
        remote: https://github.com/acme/billing.git
        revision: abc123
        specs:
          billing (1.0.0)

      GEM
        remote: https://rubygems.org/
        specs:
          railties (7.1.3)

      GEM
        remote: https://gems.acme.test/
        specs:
          acme_auth (2.0.0)

      GEM
        remote: https://rubygems.org/
        remote: https://gems.example.test/
        specs:
          devise (4.9.0)
          example_sso (1.2.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        acme_auth!
        billing!
        devise!
        example_sso!
        railties
    LOCKFILE
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
