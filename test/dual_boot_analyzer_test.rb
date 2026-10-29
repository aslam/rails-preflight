require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rails_preflight/dual_boot_analyzer"

class DualBootAnalyzerTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def write(path, content)
    file = File.join(@tmp_dir, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
  end

  def checks
    RailsPreflight::DualBootAnalyzer.new(@tmp_dir).run[:checks]
  end

  def messages
    checks.map { |check| check[:message] }
  end

  def test_suggests_dual_boot_when_missing
    write "Gemfile", "gem 'rails', '~> 7.0'\n"

    tip = checks.find { |check| check[:kind] == :tip }
    assert_match(/No dual boot found/, tip[:message])
  end

  # The Gemfile `next_rails --init` writes, with Gemfile.next a symlink to it.
  def test_finds_next_rails_setup
    write "Gemfile", "def next?\n  File.basename(__FILE__) == \"Gemfile.next\"\nend\n"
    File.symlink(File.join(@tmp_dir, "Gemfile"), File.join(@tmp_dir, "Gemfile.next"))

    assert_equal ["Dual boot is set up ('Gemfile.next')."], messages
  end

  def test_finds_bootboot_lockfile
    write "Gemfile_next.lock", ""

    assert_equal ["Dual boot is set up ('Gemfile_next.lock')."], messages
  end

  def test_flags_ci_that_skips_the_next_gemfile
    write "Gemfile.next", ""
    write ".github/workflows/ci.yml", "steps:\n  - run: bin/rails test\n"

    assert_match(/CI only runs the current Gemfile/, messages.join)
  end

  def test_ci_running_the_next_gemfile_passes
    write "Gemfile.next", ""
    write ".github/workflows/ci.yml", "env:\n  BUNDLE_GEMFILE: ${{ matrix.gemfile }}\n"

    assert(checks.none? { |check| check[:kind] })
  end

  def test_flags_ruby_versions_that_disagree
    write "Gemfile.next", ""
    write ".ruby-version", "ruby-3.2.2\n"
    write "Dockerfile", "ARG RUBY_VERSION=3.3.5\nFROM ruby:$RUBY_VERSION-slim\n"
    write ".circleci/config.yml", "docker:\n  - image: cimg/ruby:3.2\nsteps: [BUNDLE_GEMFILE=Gemfile.next]\n"

    warning = checks.find { |check| check[:status] == :warning }
    assert_equal "The Ruby version differs between files: .ruby-version 3.2.2, Dockerfile 3.3.5, .circleci/config.yml 3.2. " \
                 "Make them match, so CI tests the Ruby that runs in production.", warning[:message]
  end

  def test_ruby_versions_that_agree_at_their_precision_pass
    write "Gemfile.next", ""
    write ".ruby-version", "3.3.5\n"
    write "Dockerfile", "FROM ruby:3.3-slim\n"
    write ".github/workflows/ci.yml", "- uses: ruby/setup-ruby@v1\n  with:\n    ruby-version: '3.3'\n    BUNDLE_GEMFILE: Gemfile.next\n"

    assert(checks.none? { |check| check[:status] == :warning })
  end

  def test_ruby_matrix_is_not_compared
    write "Gemfile.next", ""
    write ".ruby-version", "3.3.5\n"
    write ".github/workflows/ci.yml", "ruby-version: ${{ matrix.ruby }}\nruby: [3.2, 3.4]\nBUNDLE_GEMFILE: Gemfile.next\n"

    assert(checks.none? { |check| check[:status] == :warning })
  end

  def test_flags_ci_that_never_runs_the_app_ruby
    write "Gemfile.next", ""
    write ".ruby-version", "3.4.1\n"
    write ".github/workflows/tests.yml", "ruby-version: '3.3'\nBUNDLE_GEMFILE: Gemfile.next\n"

    assert_match(/\.ruby-version 3\.4\.1, \.github\/workflows\/tests\.yml 3\.3\./, messages.join)
  end

  # Discourse: docs and type-publishing workflows on their own Ruby, next to the app's test workflow.
  def test_side_workflow_on_another_ruby_passes
    write "Gemfile.next", ""
    write ".ruby-version", "3.4.1\n"
    write ".github/workflows/tests.yml", "ruby-version: '3.4'\nBUNDLE_GEMFILE: Gemfile.next\n"
    write ".github/workflows/docs.yml", "ruby-version: '3.3'\n"

    assert(checks.none? { |check| check[:status] == :warning })
  end

  def test_ci_rubies_without_an_app_ruby_are_not_compared
    write "Gemfile.next", ""
    write ".github/workflows/docs.yml", "ruby-version: '3.3'\nBUNDLE_GEMFILE: Gemfile.next\n"
    write ".github/workflows/types.yml", "ruby-version: '3.4'\n"

    assert(checks.none? { |check| check[:status] == :warning })
  end
end
