# lib/rails_preflight/upgrade_analyzer.rb
require 'bundler'
require 'yaml'
require_relative 'summary_calculator'


module RailsPreflight
  class UpgradeAnalyzer
    DATA_PATH = File.expand_path('../../database/compatibility.yml', __dir__)

    # target_rails nil: the next known minor after the app's current Rails.
    def initialize(target_rails = nil, project_path = Dir.pwd)
      @target_rails = target_rails
      @project_path = project_path
      @lockfile_path = File.join(project_path, "Gemfile.lock")
      @rules = YAML.load_file(DATA_PATH)
    end

    def run
      unless File.exist?(File.join(@project_path, "config", "environment.rb"))
        raise Error, "#{@project_path} doesn't look like a Rails app (no config/environment.rb)."
      end

      defaulted = @target_rails.nil?
      if defaulted
        @target_rails = next_rails
        unless @target_rails
          puts "Rails #{current_rails} is already at or past the newest version rails-preflight knows (#{latest_known_rails}). Nothing to upgrade to."
          return
        end
      end

      puts "🔍 Starting Audit: Rails #{current_rails || 'unknown'} → #{@target_rails}..."

      results = []
      database_rules = @rules.fetch('database_rules', []).select { |rule| Gem::Version.new(rule['since']) <= Gem::Version.new(@target_rails) }

      results << check_rails_version
      results << check_ruby_version
      results << scan_gems
      results << DockerAnalyzer.new(@project_path, checked_ruby: @eol_checked_ruby).run
      results << DeprecationAnalyzer.new(@project_path, target_rails: @target_rails, current_rails: current_rails&.to_s).run
      results << ConfigAnalyzer.new(@project_path, current_rails).run
      results << DatabaseAnalyzer.new(@project_path, database_rules).run

      report_data = {
        target_rails: @target_rails,
        current_rails: current_rails&.to_s,
        results: results
      }

      # Calculate Summary
      summary_calc = SummaryCalculator.new(results, @target_rails, current_rails&.to_s, hops: upgrade_hops, app_ruby: app_ruby.first)
      report_data[:summary] = summary_calc.calculate
      summary = report_data[:summary]
      puts "Blockers: #{summary[:blockers].size} · To fix: #{summary[:to_fix].size} · Couldn't check: #{summary[:unknowns].size}"
      summary[:blockers].each { |b| puts "  ✗ #{b[:section]}: #{b[:message]}" }

      html = ReportGenerator.new(report_data).generate
      
      output_path = File.join(@project_path, "rails_preflight_report.html")
      File.write(output_path, html)
      
      puts "\n✅ Report generated at: #{output_path}"
      puts "   Open it in your browser to see the results."
      if defaulted && @target_rails != latest_known_rails
        puts "\nLatest known is #{latest_known_rails}: run `rails-preflight #{latest_known_rails}` for the full path."
      end
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

      current_str, source = app_ruby

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
        result[:checks] << { message: "Rails #{@target_rails} needs Ruby >= #{min_ver}. You have #{current_ver}.", status: :failed, fix_effort: :high }
      elsif current_ver > max_ver
        result[:status] = :failed
        result[:checks] << { message: "Rails #{@target_rails} supports Ruby up to #{constraints['max_ruby'].delete_suffix('.99')}. You have #{current_ver}.", status: :failed, fix_effort: :high }
      else
        result[:checks] << { message: "Ruby #{current_ver} (#{source}) is compatible with Rails #{@target_rails}.", status: :passed, fix_effort: :low }
      end

      @eol_checked_ruby = current_str # Docker skips this version so it isn't reported twice
      eol_below = DockerAnalyzer::RUBY_EOL_BELOW
      if current_ver < Gem::Version.new(eol_below)
        result[:status] = :warning if result[:status] == :passed
        result[:checks] << { message: "Ruby #{current_ver} is end-of-life. Upgrade to Ruby #{eol_below}+.", status: :warning, fix_effort: :high }
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

    # [version, source]; version is nil when unparseable. Handles 'ruby-2.5.9', '3.3', '3.3.5p100'.
    def app_ruby
      @app_ruby ||= begin
        raw, source = detect_app_ruby
        [raw.to_s[/\d+\.\d+(?:\.\d+)?/], source]
      end
    end

    # Rails recommends one minor version at a time: every known version after the current one, up to the target.
    def upgrade_hops
      from = current_rails && Gem::Version.new(current_rails.segments.first(2).join("."))
      to = Gem::Version.new(@target_rails)
      hops = @rules.fetch('rails_versions', {}).filter_map do |version, rules|
        v = Gem::Version.new(version)
        next unless v <= to && (from ? v > from : v == to)
        { version: version, min_ruby: rules['required_ruby'].split.last, max_ruby: rules['max_ruby'] }
      end
      hops = hops.sort_by { |hop| Gem::Version.new(hop[:version]) }
      hops << { version: @target_rails } unless target_rails_rules # target missing from compatibility.yml
      hops
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
      mixed_gems = []
      mixed_remotes = []

      lockfile_specs.each do |spec|
        next if ['rails', 'rake'].include?(spec.name)

        case gem_origin(spec)
        when :private then private_gems << spec.name
        when :mixed
          mixed_gems << spec.name
          mixed_remotes |= spec.source.remotes.map(&:to_s).reject { |r| r.include?("rubygems.org") }
        end
      end

      if private_gems.any?
        result[:status] = :warning
        result[:checks] << { message: "Private gems (#{private_gems.size}): compatibility with Rails #{@target_rails} is unknown", status: :warning, kind: :unknown, details: private_gems, fix_effort: :unknown }
      else
        result[:checks] << { message: "No private gems detected.", status: :passed, fix_effort: :low }
      end

      if mixed_gems.any?
        message = "#{mixed_gems.size} gems come from one Gemfile.lock section that lists rubygems.org and #{mixed_remotes.join(', ')}; can't tell which are private without going online"
        result[:checks] << { message: message, status: :warning, kind: :unknown, details: mixed_gems, fix_effort: :unknown }
        result[:status] = :warning
      end

      result
    end

    # Lockfile only, never the network: :public, :private (git, path, or only non-rubygems.org remotes),
    # or :mixed when one GEM section lists rubygems.org next to another remote.
    def gem_origin(spec)
      return :private unless spec.source.is_a?(Bundler::Source::Rubygems)

      remotes = spec.source.remotes.map(&:to_s)
      return :public if remotes.all? { |r| r.include?("rubygems.org") }
      remotes.none? { |r| r.include?("rubygems.org") } ? :private : :mixed
    end

    # railties is in every Rails app's lockfile, even without the rails meta-gem.
    def current_rails
      lockfile_specs.find { |s| s.name == "railties" || s.name == "rails" }&.version
    end

    # Bypass Bundler IO to avoid version mismatch errors
    def lockfile_specs
      @lockfile_specs ||= File.exist?(@lockfile_path) ? Bundler::LockfileParser.new(File.read(@lockfile_path)).specs : []
    end

    def known_rails_versions
      @rules.fetch('rails_versions', {}).keys.sort_by { |v| Gem::Version.new(v) }
    end

    def latest_known_rails
      known_rails_versions.last
    end

    # Next known minor after the current Rails (7.1.3 → 7.2), or nil when already on the newest.
    def next_rails
      unless current_rails
        reason = File.exist?(@lockfile_path) ? "No Rails in #{@lockfile_path}" : "No Gemfile.lock in #{@project_path}"
        raise Error, "#{reason}, so the current Rails version is unknown. Pass a target, e.g. `rails-preflight #{latest_known_rails}`."
      end
      current_minor = Gem::Version.new(current_rails.segments.first(2).join("."))
      known_rails_versions.find { |v| Gem::Version.new(v) > current_minor }
    end

    def target_rails_rules
      @target_rails_rules ||= @rules.fetch('rails_versions', {})[@target_rails]
    end
  end
end
