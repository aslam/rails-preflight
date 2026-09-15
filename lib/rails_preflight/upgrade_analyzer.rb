# lib/rails_preflight/upgrade_analyzer.rb
require 'bundler'
require 'net/http'
require 'json'
require 'yaml'
require 'uri'
require_relative 'summary_calculator'


module RailsPreflight
  class UpgradeAnalyzer
    DATA_PATH = File.expand_path('../../database/compatibility.yml', __dir__)

    def initialize(target_rails, project_path = Dir.pwd)
      @target_rails = target_rails
      @project_path = project_path
      @lockfile_path = File.join(project_path, "Gemfile.lock")
      @rules = YAML.load_file(DATA_PATH)
    end

    def run
      unless File.exist?(File.join(@project_path, "config", "environment.rb"))
        raise Error, "#{@project_path} doesn't look like a Rails app (no config/environment.rb)."
      end

      puts "🔍 Starting Audit: Rails #{current_rails || 'unknown'} → #{@target_rails}..."

      results = []
      database_rules = @rules.fetch('database_rules', []).select { |rule| Gem::Version.new(rule['since']) <= Gem::Version.new(@target_rails) }

      results << check_rails_version
      results << check_ruby_version
      results << scan_gems
      results << DockerAnalyzer.new(@project_path, checked_ruby: @eol_checked_ruby).run
      results << DeprecationAnalyzer.new(@project_path, target_rails: @target_rails).run
      results << ConfigAnalyzer.new(@project_path, current_rails).run
      results << DatabaseAnalyzer.new(@project_path, database_rules).run

      report_data = {
        target_rails: @target_rails,
        current_rails: current_rails&.to_s,
        results: results
      }

      # Calculate Summary
      summary_calc = SummaryCalculator.new(results, @target_rails, current_rails&.to_s)
      report_data[:summary] = summary_calc.calculate
      summary = report_data[:summary]
      puts "Blockers: #{summary[:blockers].size} · To fix: #{summary[:to_fix].size} · Couldn't check: #{summary[:unknowns].size}"

      html = ReportGenerator.new(report_data).generate
      
      output_path = File.join(@project_path, "rails_preflight_report.html")
      File.write(output_path, html)
      
      puts "\n✅ Report generated at: #{output_path}"
      puts "   Open it in your browser to see the results."
    end

    private

    def check_rails_version
      result = { title: "Rails Version", status: :passed, checks: [], confidence: :high }

      if current_rails.nil?
        result[:status] = :warning
        result[:confidence] = :low
        result[:checks] << { message: "Could not read current Rails version from Gemfile.lock.", status: :warning, kind: :unknown, fix_effort: :low }
      elsif Gem::Version.new(current_rails.segments.first(2).join(".")) >= Gem::Version.new(@target_rails)
        result[:status] = :warning
        result[:checks] << { message: "Already on Rails #{current_rails}: #{@target_rails} is not an upgrade.", status: :warning, kind: :unknown, fix_effort: :low }
      else
        result[:checks] << { message: "Rails #{current_rails} (Gemfile.lock) → #{@target_rails}", status: :passed, fix_effort: :low }
      end

      result
    end

    def check_ruby_version
      result = { title: "Ruby Version", status: :passed, checks: [], confidence: :high }

      constraints = target_rails_rules

      unless constraints
        result[:status] = :warning
        result[:checks] << { message: "Unknown Rails version: #{@target_rails}", status: :warning, kind: :unknown, fix_effort: :unknown }
        return result
      end

      # Handles 'ruby-2.5.9', '3.3', '3.3.5p100'
      current_raw, source = detect_app_ruby
      current_str = current_raw.to_s[/\d+\.\d+(?:\.\d+)?/]

      unless current_str
        result[:status] = :warning
        result[:confidence] = :low
        from = source ? " from #{source}" : " (no .ruby-version, Gemfile.lock RUBY VERSION, or ruby Dockerfile image)"
        result[:checks] << { message: "Could not determine the Ruby version used by the app#{from}. Add a .ruby-version file for an accurate check.", status: :warning, kind: :unknown, fix_effort: :low }
        return result
      end

      current_ver = Gem::Version.new(current_str)

      min_ver = Gem::Version.new(constraints['required_ruby'].split.last)
      max_ver = Gem::Version.new(constraints['max_ruby'])

      if current_ver < min_ver
        result[:status] = :failed
        result[:checks] << { message: "BLOCKER: Rails #{@target_rails} needs Ruby >= #{min_ver}. You have #{current_ver}.", status: :failed, fix_effort: :high }
      elsif current_ver > max_ver
        result[:status] = :failed
        result[:checks] << { message: "BLOCKER: Rails #{@target_rails} is NOT compatible with Ruby #{current_ver}. (Max recommended: #{max_ver}).", status: :failed, fix_effort: :high }
      else
        result[:checks] << { message: "Ruby #{current_ver} (#{source}) is compatible with Rails #{@target_rails}.", status: :passed, fix_effort: :low }
      end

      @eol_checked_ruby = current_str # Docker skips this version so it isn't reported twice
      eol_below = DockerAnalyzer::RUBY_EOL_BELOW
      if current_ver < Gem::Version.new(eol_below)
        result[:status] = :warning if result[:status] == :passed
        result[:checks] << { message: "EOL Ruby: Ruby #{current_ver} is End-of-Life. Upgrade to Ruby #{eol_below}+.", status: :warning, fix_effort: :high }
      end

      result
    end

    # First source found wins. Never falls back to the Ruby running this tool.
    def detect_app_ruby
      ruby_version_file = File.join(@project_path, ".ruby-version")
      return [File.read(ruby_version_file), ".ruby-version"] if File.exist?(ruby_version_file)

      lock_ruby = File.exist?(@lockfile_path) && File.read(@lockfile_path)[/^RUBY VERSION\s+ruby (\S+)/, 1]
      return [lock_ruby, "Gemfile.lock"] if lock_ruby

      docker_ruby = DockerAnalyzer.new(@project_path).detect_ruby_version
      [docker_ruby, "Dockerfile"] if docker_ruby
    end

    def scan_gems
      result = { title: "Private Gems", status: :passed, checks: [], confidence: :high }

      unless File.exist?(@lockfile_path)
        result[:status] = :warning
        result[:confidence] = :medium
        result[:checks] << {
          message: "No Gemfile.lock found. Skipping gem compatibility checks.",
          status: :warning,
          kind: :unknown,
          fix_effort: :low
        }
        return result
      end

      private_gems = []
      inconclusive_gems = []

      print "Checking gems "
      lockfile_specs.each do |spec|
        next if ['rails', 'rake'].include?(spec.name)

        is_priv, error = is_private?(spec)

        if error
          inconclusive_gems << { name: spec.name, error: error }
          print "?"
        elsif is_priv
          private_gems << spec.name
          print "🔒"
        else
          print "."
        end
      end
      
      puts "" # Newline after progress dots

      if private_gems.any?
        result[:status] = :warning
        result[:checks] << { message: "Private gems (#{private_gems.size}): compatibility with Rails #{@target_rails} is unknown", status: :warning, kind: :unknown, details: private_gems, fix_effort: :unknown }
      else
        result[:checks] << { message: "No private gems detected.", status: :passed, fix_effort: :low }
      end

      if inconclusive_gems.any?
        details = inconclusive_gems.map { |g| "#{g[:name]} (#{g[:error]})" }
        result[:checks] << { message: "Analysis Incomplete: Could not verify #{inconclusive_gems.size} gems", status: :warning, kind: :unknown, details: details, fix_effort: :unknown }
        result[:status] = :warning if result[:status] == :passed
      end
      
      result
    end

    def is_private?(spec)
      # Heuristic 1: If source is not Rubygems (e.g. Git, Path), assume private/custom
      return [true, nil] unless spec.source.is_a?(Bundler::Source::Rubygems)

      # Heuristic 2: Check remotes. If only rubygems.org, it's public.
      remotes = spec.source.remotes.map(&:to_s)
      return [false, nil] if remotes.all? { |r| r.include?("rubygems.org") }

      # Fallback: Check Rubygems API securely
      url = URI("https://rubygems.org/api/v1/gems/#{spec.name}.json")
      
      begin
        # Certificate errors are reported as inconclusive below, never silently trusted.
        http_options = { use_ssl: true, open_timeout: 2, read_timeout: 2 }

        response = Net::HTTP.start(url.host, url.port, http_options) do |http|
          http.request(Net::HTTP::Get.new(url))
        end
        # 404 means it's private (not found on public repo)
        [response.code == '404', nil]
      rescue StandardError => e
        # Inconclusive: surfaced as "Analysis Incomplete" in the report
        if e.is_a?(OpenSSL::SSL::SSLError)
           [false, "SSL Error: #{e.message}"]
        else
           [false, "#{e.class.name}: #{e.message}"]
        end
      end
    end

    # railties is in every Rails app's lockfile, even without the rails meta-gem.
    def current_rails
      lockfile_specs.find { |s| s.name == "railties" || s.name == "rails" }&.version
    end

    # Bypass Bundler IO to avoid version mismatch errors
    def lockfile_specs
      @lockfile_specs ||= File.exist?(@lockfile_path) ? Bundler::LockfileParser.new(File.read(@lockfile_path)).specs : []
    end

    def target_rails_rules
      @target_rails_rules ||= @rules.fetch('rails_versions', {})[@target_rails]
    end
  end
end
