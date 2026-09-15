require "minitest/autorun"
require_relative "../lib/rails_preflight/docker_analyzer"

class DockerAnalyzerTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def create_dockerfile(content)
    File.write(File.join(@tmp_dir, "Dockerfile"), content)
  end

  def test_passes_valid_dockerfile
    create_dockerfile <<~DOCKERFILE
      FROM ruby:3.4.0-alpine3.20
      RUN apk add --no-cache build-base libxml2-dev postgresql-dev tzdata
    DOCKERFILE

    analyzer = RailsPreflight::DockerAnalyzer.new(@tmp_dir)
    result = analyzer.run

    assert_equal :passed, result[:status], "Should pass valid config: #{result[:checks]}"
  end

  # Shape of the Dockerfile `rails new` generates (railties Dockerfile.tt).
  def test_rails_generated_dockerfile_has_no_false_positives
    create_dockerfile <<~DOCKERFILE
      ARG RUBY_VERSION=3.4.5
      FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base
      RUN apt-get update -qq && apt-get install --no-install-recommends -y curl libjemalloc2 libvips
      ENV RAILS_ENV="production" \\
          BUNDLE_DEPLOYMENT="1" \\
          BUNDLE_WITHOUT="development"
      FROM base AS build
      RUN bundle install
      FROM base
      ENTRYPOINT ["/rails/bin/docker-entrypoint"]
    DOCKERFILE

    analyzer = RailsPreflight::DockerAnalyzer.new(@tmp_dir)
    result = analyzer.run

    assert_equal "3.4.5", analyzer.detect_ruby_version
    assert_equal :passed, result[:status], "Unexpected findings: #{result[:checks]}"
  end

  def test_detects_two_part_ruby_tag
    create_dockerfile "FROM ruby:3.3-slim\n"

    assert_equal "3.3", RailsPreflight::DockerAnalyzer.new(@tmp_dir).detect_ruby_version
  end

  def test_detects_eol_ruby
    create_dockerfile <<~DOCKERFILE
      FROM ruby:2.7.6
    DOCKERFILE

    analyzer = RailsPreflight::DockerAnalyzer.new(@tmp_dir)
    result = analyzer.run

    assert_equal :warning, result[:status]
    assert result[:checks].any? { |c| c[:message].include?("end-of-life") }
  end

  def test_detects_eol_node
    create_dockerfile <<~DOCKERFILE
      FROM ruby:3.4.0
      ENV NODE_VERSION 12.0.0
    DOCKERFILE

    analyzer = RailsPreflight::DockerAnalyzer.new(@tmp_dir)
    result = analyzer.run

    assert result[:checks].any? { |c| c[:message].include?("Node 12 is end-of-life") }
  end

  def test_detects_missing_locale_and_tzdata_on_non_ruby_base
    create_dockerfile <<~DOCKERFILE
      FROM ubuntu:24.04
      RUN apt-get install -y ruby-full
    DOCKERFILE

    analyzer = RailsPreflight::DockerAnalyzer.new(@tmp_dir)
    result = analyzer.run

    assert result[:checks].any? { |c| c[:message].include?("LANG") }
    assert result[:checks].any? { |c| c[:message].include?("tzdata") }
  end

  def test_detects_missing_tzdata_on_alpine
    create_dockerfile <<~DOCKERFILE
      FROM ruby:3.4.0-alpine3.20
      RUN apk add --no-cache build-base
    DOCKERFILE

    result = RailsPreflight::DockerAnalyzer.new(@tmp_dir).run

    assert result[:checks].any? { |c| c[:message].include?("tzdata") }
  end

  def test_detects_openssl_mismatch_alpine
    # Alpine 3.17+ uses OpenSSL 3.0, Ruby < 3.1 has issues
    create_dockerfile <<~DOCKERFILE
      FROM ruby:2.7.6-alpine3.17
      RUN apk add tzdata
    DOCKERFILE

    analyzer = RailsPreflight::DockerAnalyzer.new(@tmp_dir)
    result = analyzer.run

    assert result[:checks].any? { |c| c[:message].include?("OpenSSL 3") }
  end

  def test_old_alpine_is_not_flagged_for_openssl_3
    # Float comparison used to read 3.9 as newer than 3.17
    create_dockerfile "FROM ruby:2.6-alpine3.9\nRUN apk add tzdata\n"

    result = RailsPreflight::DockerAnalyzer.new(@tmp_dir).run

    refute result[:checks].any? { |c| c[:message].include?("OpenSSL") }
  end

  def test_skips_eol_ruby_the_ruby_section_already_reported
    create_dockerfile "FROM ruby:2.7\n"

    same_minor = RailsPreflight::DockerAnalyzer.new(@tmp_dir, checked_ruby: "2.7.6").run
    different = RailsPreflight::DockerAnalyzer.new(@tmp_dir, checked_ruby: "3.4.1").run

    refute same_minor[:checks].any? { |c| c[:message].include?("end-of-life") }
    assert different[:checks].any? { |c| c[:message].include?("end-of-life") }
  end
end
