# lib/rails_preflight/docker_analyzer.rb
module RailsPreflight
  class DockerAnalyzer
    # Update when a release goes EOL: Ruby 3.2 (2026-03-31), Node 20 (2026-04-30).
    RUBY_EOL_BELOW = "3.3"
    NODE_EOL_BELOW = 22

    # Official image, with or without registry prefix: `ruby:3.3`, `docker.io/library/ruby:$RUBY_VERSION-slim`.
    RUBY_IMAGE = %r{^\s*FROM\s+(?:--platform=\S+\s+)?(?:\S+/)?ruby:(\S+)}i

    # checked_ruby: app Ruby the Ruby Version section already checked for EOL
    def initialize(root_path = Dir.pwd, checked_ruby: nil)
      @dockerfile_path = File.join(root_path, "Dockerfile")
      @checked_ruby = checked_ruby
    end

    # Version from the ruby image tag, resolving ARG defaults as in Rails' generated Dockerfile.
    def detect_ruby_version
      return nil unless File.exist?(@dockerfile_path)
      content = File.read(@dockerfile_path)
      match = content.match(RUBY_IMAGE)
      return nil unless match

      args = content.scan(/^\s*ARG\s+(\w+)=["']?([^\s"']+)/).to_h
      match[1].gsub(/\$\{?(\w+)\}?/) { args[$1].to_s }[/\A\d+\.\d+(?:\.\d+)?/]
    end

    def run
      result = { title: "Docker Configuration", status: :passed, checks: [], confidence: :medium }

      unless File.exist?(@dockerfile_path)
        result[:checks] << { message: "No Dockerfile found. Docker checks skipped.", status: :passed }
        return result
      end

      content = File.read(@dockerfile_path)
      ruby_version = detect_ruby_version
      # Official ruby images set LANG=C.UTF-8, and their Debian variants ship tzdata.
      official_ruby = content.match?(RUBY_IMAGE)
      alpine = content.match?(/alpine/)

      check_ruby_version(ruby_version, result)
      check_package_manager_pitfalls(content, result)
      check_alpine_pitfalls(content, result) if alpine
      check_node_version(content, result)
      check_eol_base_image(ruby_version, result)
      check_locale(content, result) unless official_ruby
      check_tzdata(content, result) if alpine || !official_ruby
      check_openssl_mismatch(content, ruby_version, result)

      update_overall_status(result)
      result
    end

    private

    def check_ruby_version(ruby_version, result)
      if ruby_version
        result[:checks] << { message: "Dockerfile uses Ruby #{ruby_version} base image", status: :passed, fix_effort: :low }
      else
        result[:checks] << { message: "Could not detect a versioned ruby base image in Dockerfile.", status: :warning, kind: :unknown, fix_effort: :medium }
      end
    end

    def check_package_manager_pitfalls(content, result)
      if content.include?("bundle install") && !content.match?(/without/i)
        result[:checks] << { message: "'bundle install' also installs development and test gems. Set BUNDLE_WITHOUT=\"development:test\".", status: :passed, kind: :tip, fix_effort: :low }
      end
    end

    def check_alpine_pitfalls(content, result)
      unless content.match?(/build-base|libxml2-dev|postgresql-dev/)
        result[:checks] << { message: "Alpine image without build-base: gems with native extensions may fail to install. Add 'apk add build-base'.", status: :warning, fix_effort: :medium }
      end
    end

    def check_node_version(content, result)
      # Support ENV NODE_VERSION 12.0.0 (space) and ENV NODE_VERSION=12.0.0 (equals)
      if match = content.match(/NODE_VERSION\s*[:=\s]\s*['"]?(\d+)/)
        major_version = match[1].to_i
        if major_version < NODE_EOL_BELOW
          result[:checks] << { message: "Node #{major_version} is end-of-life. Upgrade to Node #{NODE_EOL_BELOW}+.", status: :warning, fix_effort: :medium }
        end
      end
    end

    def check_eol_base_image(ruby_version, result)
      # EOL is per minor version; same minor as the checked app Ruby was already reported
      return if ruby_version && @checked_ruby && ruby_version.split(".").first(2) == @checked_ruby.split(".").first(2)

      if ruby_version && Gem::Version.new(ruby_version) < Gem::Version.new(RUBY_EOL_BELOW)
        result[:checks] << { message: "Dockerfile Ruby #{ruby_version} is end-of-life. Upgrade to Ruby #{RUBY_EOL_BELOW}+.", status: :warning, fix_effort: :high }
      end
    end

    def check_locale(content, result)
      unless content.match?(/^\s*ENV\s+(LANG|LC_ALL)/)
        result[:checks] << { message: "No ENV LANG or LC_ALL set, which can cause encoding errors.", status: :warning, fix_effort: :low }
      end
    end

    def check_tzdata(content, result)
      unless content.match?(/tzdata/)
        result[:checks] << { message: "tzdata isn't installed. Time zone lookups need it, or the tzinfo-data gem.", status: :warning, fix_effort: :low }
      end
    end

    def check_openssl_mismatch(content, ruby_version, result)
      # Alpine >= 3.17 ships OpenSSL 3, which Ruby < 3.1's openssl gem doesn't support.
      alpine_version = content[/alpine(\d+\.\d+)/, 1]
      return unless ruby_version && alpine_version

      if Gem::Version.new(alpine_version) >= Gem::Version.new("3.17") && Gem::Version.new(ruby_version) < Gem::Version.new("3.1")
        result[:checks] << { message: "Alpine #{alpine_version} ships OpenSSL 3, which Ruby #{ruby_version} (< 3.1) does not support.", status: :warning, fix_effort: :high }
      end
    end

    def update_overall_status(result)
      if result[:checks].any? { |c| c[:status] != :passed }
        result[:status] = :warning
      end
    end
  end
end
