# lib/rails_upgrade_audit/upgrade_analyzer.rb
require 'bundler'
require 'net/http'
require 'json'
require 'yaml'
require 'uri'


module RailsUpgradeAudit
  class UpgradeAnalyzer
    DATA_PATH = File.expand_path('../../database/compatibility.yml', __dir__)

    def initialize(target_rails, project_path = Dir.pwd)
      @target_rails = target_rails
      @project_path = project_path
      @lockfile_path = File.join(project_path, "Gemfile.lock")
      @rules = YAML.load_file(DATA_PATH)
    end

    def run
      puts "🔍 Starting Audit for Rails #{@target_rails} (Generating HTML Report)..."
      
      results = []
      
      results << check_ruby_version
      results << scan_gems
      results << DockerAnalyzer.new(@project_path).run
      results << DeprecationAnalyzer.new(@project_path).run
      results << ConfigAnalyzer.new(@project_path).run
      results << DatabaseAnalyzer.new(@project_path, @rules['rails_versions'][@target_rails]['database_rules']).run

      report_data = {
        target_rails: @target_rails,
        results: results
      }

      html = ReportGenerator.new(report_data).generate
      
      output_path = File.join(@project_path, "upgrade_audit.html")
      File.write(output_path, html)
      
      puts "\n✅ Report generated at: #{output_path}"
      puts "   Open it in your browser to see the results."
    end

    private

    def check_ruby_version
      result = { title: "Ruby Version", status: :passed, checks: [] }
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
      constraints = @rules['rails_versions'][@target_rails]

      unless constraints
        result[:status] = :warning
        result[:checks] << { message: "Unknown Rails version: #{@target_rails}", status: :warning }
        return result
      end

      min_ver = Gem::Version.new(constraints['required_ruby'].split.last)
      max_ver = Gem::Version.new(constraints['max_ruby'])

      if current_ver < min_ver
        result[:status] = :failed
        result[:checks] << { message: "BLOCKER: Rails #{@target_rails} needs Ruby >= #{min_ver}. You have #{current_ver}.", status: :failed }
      elsif current_ver > max_ver
        result[:status] = :failed
        result[:checks] << { message: "BLOCKER: Rails #{@target_rails} is NOT compatible with Ruby #{current_ver}. (Max recommended: #{max_ver}).", status: :failed }
      else
        result[:checks] << { message: "Ruby #{current_ver} (#{source}) is compatible.", status: :passed }
      end
      
      result
    end

    def scan_gems
      result = { title: "Private Gems", status: :passed, checks: [] }
      puts "\n[2/2] Scanning Gems..."

      # Bypass Bundler IO to avoid version mismatch errors
      content = File.read(@lockfile_path)
      parser = Bundler::LockfileParser.new(content)

      private_gems = []

      parser.specs.each do |spec|
        next if ['rails', 'rake'].include?(spec.name)

        if is_private?(spec)
          private_gems << spec.name
          print "🔒"
        else
          print "."
        end
      end
      
      puts "" # Newline after progress dots

      if private_gems.any?
        result[:status] = :warning
        result[:checks] << { message: "Private Gems Detected", status: :warning, details: private_gems }
      else
        result[:checks] << { message: "No private gems detected.", status: :passed }
      end
      
      result
    end

    def is_private?(spec)
      # Heuristic 1: If source is not Rubygems (e.g. Git, Path), assume private/custom
      return true unless spec.source.is_a?(Bundler::Source::Rubygems)

      # Heuristic 2: Check remotes. If only rubygems.org, it's public.
      remotes = spec.source.remotes.map(&:to_s)
      return false if remotes.all? { |r| r.include?("rubygems.org") }

      # Fallback: Check Rubygems API securely
      url = URI("https://rubygems.org/api/v1/gems/#{spec.name}.json")
      
      begin
        response = Net::HTTP.start(url.host, url.port, use_ssl: true, open_timeout: 2, read_timeout: 2) do |http|
          http.request(Net::HTTP::Get.new(url))
        end
        response.code == '404'
      rescue StandardError
        # Fail safe - if we can't verify, don't scream "Private", but maybe we should?
        # For now, let's assume if we can't find it on public internet and it has mixed sources, it might be private.
        # But to avoid false positives on network errors, we'll return false (assumed public) or handle strictly?
        # Given the user request "Gracefully degrade", we'll return false but maybe log invisible warning?
        # Actually returning true (Private) on valid network error is annoying.
        # Let's return false (Assume public) on network failure to avoid blocking, 
        # as this is just an audit tool.
        false
      end
    end
  end
end
