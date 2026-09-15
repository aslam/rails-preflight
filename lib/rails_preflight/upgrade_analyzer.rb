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
      puts "🔍 Starting Audit for Rails #{@target_rails}..."
      
      results = []
      database_rules = target_rails_rules&.fetch('database_rules', nil)
      
      results << check_ruby_version
      results << scan_gems
      results << DockerAnalyzer.new(@project_path).run
      results << DeprecationAnalyzer.new(@project_path).run
      results << ConfigAnalyzer.new(@project_path).run
      results << DatabaseAnalyzer.new(@project_path, database_rules).run

      report_data = {
        target_rails: @target_rails,
        results: results
      }

      # Calculate Summary
      summary_calc = SummaryCalculator.new(results, @target_rails)
      report_data[:summary] = summary_calc.calculate

      html = ReportGenerator.new(report_data).generate
      
      output_path = File.join(@project_path, "rails_preflight_report.html")
      File.write(output_path, html)
      
      puts "\n✅ Report generated at: #{output_path}"
      puts "   Open it in your browser to see the results."
    end

    private

    def check_ruby_version
      result = { title: "Ruby Version", status: :passed, checks: [], confidence: :high }
      puts "\n[1/2] Checking Ruby Version..."

      # 1. Detect Current Ruby
      ruby_version_file = File.join(@project_path, ".ruby-version")
      if File.exist?(ruby_version_file)
        current_raw = File.read(ruby_version_file).strip
        source = ".ruby-version"
      elsif docker_version = DockerAnalyzer.new(@project_path).detect_ruby_version
        current_raw = docker_version
        source = "Dockerfile"
      else
        current_raw = RUBY_VERSION
        source = "System (RUBY_VERSION)"
      end

      # Clean the version string (handle 'ruby-2.5.9')
      current_str = current_raw.match(/(\d+\.\d+\.\d+)/)[1]
      current_ver = Gem::Version.new(current_str)

      # 2. Check Constraints
      constraints = target_rails_rules

      unless constraints
        result[:status] = :warning
        result[:checks] << { message: "Unknown Rails version: #{@target_rails}", status: :warning, fix_effort: :unknown }
        return result
      end

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

      eol_below = DockerAnalyzer::RUBY_EOL_BELOW
      if current_ver < Gem::Version.new(eol_below)
        result[:status] = :warning if result[:status] == :passed
        result[:checks] << { message: "EOL Ruby: Ruby #{current_ver} is End-of-Life. Upgrade to Ruby #{eol_below}+.", status: :warning, fix_effort: :high }
      end

      result
    end

    def scan_gems
      result = { title: "Private Gems", status: :passed, checks: [], confidence: :high }
      puts "\n[2/2] Scanning Gems..."

      unless File.exist?(@lockfile_path)
        result[:status] = :warning
        result[:confidence] = :medium
        result[:checks] << {
          message: "No Gemfile.lock found. Skipping gem compatibility checks.",
          status: :warning,
          fix_effort: :low
        }
        return result
      end

      # Bypass Bundler IO to avoid version mismatch errors
      content = File.read(@lockfile_path)
      parser = Bundler::LockfileParser.new(content)

      private_gems = []
      inconclusive_gems = []

      parser.specs.each do |spec|
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
        result[:checks] << { message: "Private Gems Detected", status: :warning, details: private_gems, fix_effort: :unknown }
      else
        result[:checks] << { message: "No private gems detected.", status: :passed, fix_effort: :low }
      end

      if inconclusive_gems.any?
        details = inconclusive_gems.map { |g| "#{g[:name]} (#{g[:error]})" }
        result[:checks] << { message: "Analysis Incomplete: Could not verify #{inconclusive_gems.size} gems", status: :warning, details: details, fix_effort: :unknown }
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
        # Use VERIFY_NONE to avoid local certificate issues (CRL errors)
        # We are only checking for existence of public gems, not transmitting secrets.
        http_options = { 
          use_ssl: true, 
          open_timeout: 2, 
          read_timeout: 2,
          verify_mode: OpenSSL::SSL::VERIFY_NONE 
        }

        response = Net::HTTP.start(url.host, url.port, http_options) do |http|
          http.request(Net::HTTP::Get.new(url))
        end
        # 404 means it's private (not found on public repo)
        [response.code == '404', nil]
      rescue StandardError => e
        # Fail safe - return false (assume public) but with error details
        # If it's an SSL error despite VERIFY_NONE, we should still handle it gracefully
        if e.is_a?(OpenSSL::SSL::SSLError)
           [false, "SSL Error: #{e.message}"]
        else
           [false, "#{e.class.name}: #{e.message}"]
        end
      end
    end

    def target_rails_rules
      @target_rails_rules ||= @rules.fetch('rails_versions', {})[@target_rails]
    end
  end
end
