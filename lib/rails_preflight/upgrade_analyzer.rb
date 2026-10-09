# lib/rails_preflight/upgrade_analyzer.rb
require 'bundler'
require 'json'
require 'net/http'
require 'yaml'
require_relative 'summary_calculator'


module RailsPreflight
  class UpgradeAnalyzer
    DATA_PATH = File.expand_path('../../database/compatibility.yml', __dir__)

    # target_rails nil: the next known minor after the app's current Rails.
    # offline: never call the network; gems the lockfile can't place are reported as "couldn't check",
    # and gem release dates aren't looked up.
    # format: :html writes the report into the app; :markdown and :json print it on stdout, with progress on stderr.
    # run returns the summary (nil when there's nothing to upgrade to), so the caller can set the exit code.
    def initialize(target_rails = nil, project_path = Dir.pwd, offline: false, format: :html)
      @target_rails = target_rails
      @offline = offline
      @format = format
      @out = format == :html ? $stdout : $stderr
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
          @out.puts "Rails #{current_rails} is already at or past the newest version rails-preflight knows (#{latest_known_rails}). Nothing to upgrade to."
          return
        end
      end

      @out.puts "🔍 Starting Audit: Rails #{current_rails || 'unknown'} → #{@target_rails}..."

      results = []
      database_rules = @rules.fetch('database_rules', []).select { |rule| Gem::Version.new(rule['since']) <= Gem::Version.new(@target_rails) }

      results << check_rails_version
      results << check_ruby_version
      results << scan_gems
      results << DockerAnalyzer.new(@project_path, checked_ruby: @eol_checked_ruby).run
      results << GemAnalyzer.new(@project_path, lockfile_specs, hops: upgrade_hops.map { |hop| hop[:version] }, direct: lockfile&.dependencies&.keys || [],
                                 last_releases: (@last_releases || {} unless @offline), target_released: target_rails_rules&.dig('released')).run
      results << DeprecationAnalyzer.new(@project_path, target_rails: @target_rails, current_rails: current_rails&.to_s).run
      results << ConfigAnalyzer.new(@project_path, current_rails).run
      results << DatabaseAnalyzer.new(@project_path, database_rules).run

      report_data = {
        app: File.basename(File.expand_path(@project_path)),
        target_rails: @target_rails,
        current_rails: current_rails&.to_s,
        ruby: app_ruby,
        offline: @offline,
        looked_up: @looked_up,
        later_rails: known_rails_versions.select { |v| Gem::Version.correct?(@target_rails) && Gem::Version.new(v) > Gem::Version.new(@target_rails) },
        results: results
      }

      # Calculate Summary
      summary_calc = SummaryCalculator.new(results, @target_rails, current_rails&.to_s, hops: upgrade_hops, app_ruby: app_ruby.first,
                                           current_max_ruby: current_rails_rules&.dig('max_ruby'))
      report_data[:summary] = summary_calc.calculate
      summary = report_data[:summary]
      @out.puts "#{"Already broken: #{summary[:broken].size} · " if summary[:broken].any?}Blockers: #{summary[:blockers].size} · To fix: #{summary[:to_fix].size} · Couldn't check: #{summary[:unknowns].size}"
      summary[:broken].each { |b| @out.puts "  ‼ #{b[:section]}: #{b[:message]}" }
      summary[:blockers].each { |b| @out.puts "  ✗ #{b[:section]}: #{b[:message]}" }

      if (report = { markdown: MarkdownReport, json: JsonReport }[@format])
        $stdout.print report.new(report_data).generate
      else
        output_path = File.join(@project_path, "rails_preflight_report.html")
        File.write(output_path, ReportGenerator.new(report_data).generate)
        @out.puts "\n✅ Report generated at: #{output_path}"
        @out.puts "   Open it in your browser to see the results."
      end
      if defaulted && @target_rails != latest_known_rails
        @out.puts "\nLatest known is #{latest_known_rails}: run `rails-preflight #{latest_known_rails}` for the full path."
      end
      summary
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
        result[:checks] << { message: "Already on Rails #{current_rails}: #{@target_rails} is not an upgrade.", status: :passed }
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
        advice =
          if max_ver >= Gem::Version.new(eol_below) then "Upgrade to Ruby #{eol_below}+."
          else
            later = @rules['rails_versions'].find { |_, rules| Gem::Version.new(rules['max_ruby']) >= Gem::Version.new(eol_below) }&.first
            "Rails #{@target_rails} supports up to Ruby #{constraints['max_ruby'].delete_suffix('.99')}; Ruby #{eol_below}+ needs Rails #{later || 'newer than ' + latest_known_rails}."
          end
        result[:checks] << { message: "Ruby #{current_ver} is end-of-life. #{advice}", status: :warning, fix_effort: :high }
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
      dated_gems = [] # public gems that depend on Rails: their last release date is looked up

      lockfile_specs.each do |spec|
        next if ['rails', 'rake'].include?(spec.name)

        origin = gem_origin(spec)
        case origin
        when :private then private_gems << spec.name
        when :mixed
          mixed_gems << spec.name
          mixed_remotes |= spec.source.remotes.map(&:to_s).reject { |r| rubygems_org?(r) }
        end
        dated_gems << spec.name if origin != :private && depends_on_rails?(spec)
      end

      if mixed_gems.any? && @offline
        message = "#{mixed_gems.size} gems come from one Gemfile.lock section that lists rubygems.org and #{mixed_remotes.join(', ')}; can't tell which are private with --offline"
        result[:checks] << { message: message, status: :warning, kind: :unknown, names: mixed_gems, fix_effort: :unknown }
        result[:status] = :warning
      end

      unless @offline || (mixed_gems | dated_gems).empty?
        names = mixed_gems | dated_gems
        @looked_up = names.size
        @out.puts "Looking up #{names.size} gems on rubygems.org (--offline skips this)..."
        found, inconclusive = lookup_on_rubygems(names)
        private_gems.concat(mixed_gems.select { |name| found[name] == false })
        @last_releases = dated_gems.filter_map { |name| [name, found[name]['version_created_at']] if found[name].is_a?(Hash) && found[name]['version_created_at'] }.to_h
        if mixed_gems.any?
          result[:checks] << { message: "Looked up #{mixed_gems.size} gems on rubygems.org, since Gemfile.lock lists them under both rubygems.org and #{mixed_remotes.join(', ')}. Pass --offline to skip.", status: :passed, fix_effort: :low }
        end
        if inconclusive.any?
          names = inconclusive.map { |name, error| "#{name} (#{error})" }
          result[:checks] << { message: "Could not verify #{inconclusive.size} gems against rubygems.org", status: :warning, kind: :unknown, names: names, fix_effort: :unknown }
          result[:status] = :warning
        end
      end

      if private_gems.any?
        result[:status] = :warning
        result[:checks].unshift({ message: "Private gems (#{private_gems.size}): compatibility with Rails #{@target_rails} is unknown", status: :warning, kind: :unknown, names: private_gems.sort, fix_effort: :unknown })
      else
        result[:checks].unshift({ message: "No private gems detected.", status: :passed, fix_effort: :low })
      end

      result
    end

    # 200 on rubygems.org means public, 404 private, anything else unchecked.
    # Returns [{ name => gem info Hash (public) or false (private) }, { name => error }].
    # Only public gems and gem names the lockfile can't place are sent; never git, path or private-registry-only gems.
    def lookup_on_rubygems(names)
      queue = Queue.new
      names.each { |name| queue << name }
      found = {}
      inconclusive = {}
      lock = Mutex.new

      Array.new([names.size, 8].min) do
        Thread.new do
          while (name = (queue.pop(true) rescue nil))
            begin
              url = URI("https://rubygems.org/api/v1/gems/#{name}.json")
              # Certificate errors are reported as inconclusive, never silently trusted.
              response = Net::HTTP.start(url.host, url.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
                http.request(Net::HTTP::Get.new(url))
              end
              raise "HTTP #{response.code}" unless %w[200 404].include?(response.code) # e.g. 429 when rate limited
              info = response.code == "200" && (JSON.parse(response.body.to_s) rescue {})
              lock.synchronize { found[name] = info }
            rescue StandardError => e
              lock.synchronize { inconclusive[name] = "#{e.class.name}: #{e.message}" }
            end
          end
        end
      end.each(&:join)

      [found, inconclusive]
    end

    # From the lockfile: :public, :private (git, path, or only non-rubygems.org remotes), or, when one GEM
    # section lists rubygems.org next to another remote (Bundler before 2.2), whatever the Gemfile says; :mixed if it doesn't.
    def gem_origin(spec)
      return :private unless spec.source.is_a?(Bundler::Source::Rubygems)

      remotes = spec.source.remotes.map(&:to_s)
      return :public if remotes.all? { |r| rubygems_org?(r) }
      return :private if remotes.none? { |r| rubygems_org?(r) }

      global, scoped = gemfile_sources
      if scoped.key?(spec.name)
        rubygems_org?(scoped[spec.name]) ? :public : :private
      elsif global.any? && global.all? { |r| rubygems_org?(r) }
        # ponytail: dependencies of scoped gems count as public; Bundler 1.x could resolve them from the scoped source too.
        :public
      else
        :mixed
      end
    end

    def depends_on_rails?(spec)
      !GemAnalyzer::RAILS_GEMS.include?(spec.name) && spec.dependencies.any? { |dep| GemAnalyzer::RAILS_GEMS.include?(dep.name) }
    end

    def rubygems_org?(remote)
      remote.include?("rubygems.org")
    end

    # Read, never evaluated: the Gemfile is the app's code. Returns [global sources, { gem name => source }]
    # from `source "…" do` blocks and `gem "…", source: "…"`. A source written as code (`ENV.fetch(…)`) is kept
    # as that code, which never reads as rubygems.org, so its gems count as private.
    # ponytail: line-based; one-line `do … end` or `{ … }` blocks fall back to the rubygems.org lookup,
    # and `x = if … end` closes a block early. Parse with Ripper if real Gemfiles hit these.
    def gemfile_sources
      @gemfile_sources ||= begin
        global = []
        scoped = {}
        blocks = [] # source for a `source … do` block, nil for any other block
        gemfile_lines(File.join(@project_path, "Gemfile")).each do |line|
          source = line[/^\s*source\b\s*\(?\s*(.+?)\s*\)?\s*(?:do\b.*)?$/, 1]&.delete_prefix("\"")&.delete_suffix("\"")&.delete("'")
          name = line[/^\s*gem\s*\(?\s*["']([^"']+)["']/, 1]
          if name
            option = line[/\bsource:\s*(.+?)\s*(?:,|\)|$)/, 1]&.delete("\"'")
            scoped[name] = option || blocks.compact.last
            scoped.delete(name) unless scoped[name]
          end
          if line =~ /\bdo\s*(\|[^|]*\|)?\s*$/ || line =~ /^\s*(if|unless|case|begin|while|until|def)\b/
            blocks << source
          elsif source
            global << source
          elsif line =~ /^\s*end\b/
            blocks.pop
          end
        end
        [global, scoped]
      end
    end

    # Comments stripped, `gem "x",` joined with its next line, and quoted `eval_gemfile` paths read in place.
    def gemfile_lines(path, seen = [])
      return [] if !File.exist?(path) || seen.include?(path)

      seen << path
      text = File.read(path).gsub(/#(?!\{).*/, "").gsub(/,\s*\n\s*/, ", ")
      text.lines.flat_map do |line|
        included = line[/^\s*eval_gemfile\s*\(?\s*["']([^"']+)["']/, 1]
        included ? gemfile_lines(File.expand_path(included, File.dirname(path)), seen) : [line]
      end
    end

    # railties is in every Rails app's lockfile, even without the rails meta-gem.
    def current_rails
      lockfile_specs.find { |s| s.name == "railties" || s.name == "rails" }&.version
    end

    # Bypass Bundler IO to avoid version mismatch errors
    def lockfile_specs
      lockfile&.specs || []
    end

    def lockfile
      return @lockfile if defined?(@lockfile)
      @lockfile = File.exist?(@lockfile_path) ? Bundler::LockfileParser.new(File.read(@lockfile_path)) : nil
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

    def current_rails_rules
      current_rails && @rules.fetch('rails_versions', {})[current_rails.segments.first(2).join(".")]
    end

    def target_rails_rules
      @target_rails_rules ||= @rules.fetch('rails_versions', {})[@target_rails]
    end
  end
end
