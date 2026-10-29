# lib/rails_preflight/dual_boot_analyzer.rb
require_relative 'docker_analyzer'

module RailsPreflight
  # Before the first step: can the app boot both Rails versions, does CI test both, and do the places
  # that name a Ruby agree on it.
  class DualBootAnalyzer
    CI_GLOBS = %w[.github/workflows/*.{yml,yaml} .circleci/config.yml .gitlab-ci.yml .travis.yml].freeze
    NEXT_RAILS = "https://github.com/fastruby/next_rails"
    # next_rails runs the next boot with BUNDLE_GEMFILE=Gemfile.next; bootboot with DEPENDENCIES_NEXT=1.
    CI_RUNS_NEXT = /Gemfile\.next|BUNDLE_GEMFILE|DEPENDENCIES_NEXT/
    # setup-ruby's `ruby-version: 3.3`, and image tags such as `ruby:3.3` or `cimg/ruby:3.3.5`. A matrix
    # (`ruby-version: ${{ matrix.ruby }}`) isn't resolved, so it's never compared.
    CI_RUBY = /(?:ruby-version:\s*["']?|\bruby:)(\d+\.\d+(?:\.\d+)?)/

    def initialize(root_path = Dir.pwd)
      @root_path = root_path
    end

    def run
      result = { title: "Dual Boot", status: :passed, checks: [], confidence: :medium }
      ci = Dir.glob(CI_GLOBS.map { |glob| File.join(@root_path, glob) }).sort.to_h { |file| [relative(file), File.read(file, encoding: "UTF-8")] }

      if (setup = dual_boot)
        if ci.any? && ci.values.none? { |content| content.match?(CI_RUNS_NEXT) }
          result[:checks] << { message: "Dual boot is set up (#{setup}), but CI only runs the current Gemfile. Add a CI job with 'BUNDLE_GEMFILE=Gemfile.next', so each step is tested on the next Rails before it ships.",
                               status: :passed, kind: :tip, fix_effort: :low, source: NEXT_RAILS }
        else
          result[:checks] << { message: "Dual boot is set up (#{setup}).", status: :passed }
        end
      else
        result[:checks] << { message: "No dual boot found (no 'Gemfile.next' or 'next?' in the Gemfile). Set it up first, e.g. with next_rails, so the app and its tests run on the current and the next Rails while each step is in progress.",
                             status: :passed, kind: :tip, fix_effort: :low, source: NEXT_RAILS }
      end

      check_ruby_versions(ci, result)
      result
    end

    private

    def dual_boot
      gemfile = File.join(@root_path, "Gemfile")
      if File.exist?(File.join(@root_path, "Gemfile.next")) then "'Gemfile.next'"
      elsif File.exist?(File.join(@root_path, "Gemfile_next.lock")) then "'Gemfile_next.lock'"
      elsif File.exist?(gemfile) && File.read(gemfile, encoding: "UTF-8").match?(/^\s*def\s+next\?/) then "'next?' in the Gemfile"
      end
    end

    # .ruby-version and the Dockerfile name the Ruby the app runs on, so they must agree. CI only has to test
    # that Ruby somewhere: a matrix or a side workflow (docs, linting) on another Ruby is fine.
    def check_ruby_versions(ci, result)
      ruby_version_file = File.join(@root_path, ".ruby-version")
      app = [[".ruby-version", File.exist?(ruby_version_file) && File.read(ruby_version_file)[/\d+\.\d+(?:\.\d+)?/]],
             ["Dockerfile", DockerAnalyzer.new(@root_path).detect_ruby_version]].select(&:last)
      return if app.empty?

      ci_rubies = ci.flat_map { |file, content| content.scan(CI_RUBY).flatten.uniq.map { |version| [file, version] } }
      app_ruby = app.first.last
      differ = app.map(&:last).any? { |version| !same?(version, app_ruby) } ||
               (ci_rubies.any? && ci_rubies.none? { |_, version| same?(version, app_ruby) })
      return unless differ

      result[:status] = :warning
      result[:checks] << { message: "The Ruby version differs between files: #{(app + ci_rubies).map { |source, version| "#{source} #{version}" }.join(', ')}. Make them match, so CI tests the Ruby that runs in production.",
                           status: :warning, fix_effort: :low }
    end

    # 3.3 and 3.3.5 agree; 3.3 and 3.4 don't.
    def same?(a, b)
      a, b = [a, b].map { |version| version.split(".") }
      a.first(b.size) == b.first(a.size)
    end

    def relative(file)
      file.delete_prefix(File.join(@root_path, ""))
    end
  end
end
