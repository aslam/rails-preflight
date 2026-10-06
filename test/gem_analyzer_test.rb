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
    assert_nil check[:removed_in]
    assert_includes check[:message], "It doesn't work from Rails 7.0, so plan the move before then. Used in 0 files."
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
