module RailsPreflight
  # Gems that stop working, or are on their way out, across the upgrade: Rails limits their locked versions
  # declare in Gemfile.lock, plus the curated list in database/gems.yml for limits only a README states.
  class GemAnalyzer
    DATA_PATH = File.expand_path('../../database/gems.yml', __dir__)
    RAILS_GEMS = %w[rails railties actioncable actionmailbox actionmailer actionpack actiontext actionview
                    activejob activemodel activerecord activestorage activesupport].freeze

    # specs: Gemfile.lock specs. hops: the Rails minors the upgrade passes through, after the current one, ending at the target.
    # direct: gem names the Gemfile lists (Gemfile.lock DEPENDENCIES).
    def initialize(project_path, specs, hops:, direct: [], database_path: DATA_PATH)
      @project_path = project_path
      @specs = specs
      @hops = hops
      @direct = direct
      data = YAML.load_file(database_path)
      @entries = data.fetch('gems', [])
      @adapter_requirements = data.fetch('adapter_requirements', {})
      @dropped_by_rails = data.fetch('dropped_by_rails', {})
    end

    def run
      result = { title: "Gem Compatibility", status: :passed, checks: [], confidence: :medium }
      return result if @hops.empty? # already on the target
      result[:checks].concat(locked_limits, adapter_limits, dropped_by_rails, curated)

      if result[:checks].empty?
        result[:checks] << { message: "No locked gem limits Rails below #{@hops.last}, and none is on the list of retired gems.", status: :passed }
      else
        statuses = result[:checks].map { |c| c[:status] }
        result[:status] = statuses.include?(:failed) ? :failed : :warning
      end
      result
    end

    private

    # A gem whose locked version requires, say, railties < 6.1 blocks the 6.1 hop until it's upgraded or replaced.
    def locked_limits
      @specs.filter_map do |spec|
        next if RAILS_GEMS.include?(spec.name)

        limits = spec.dependencies.select { |dep| RAILS_GEMS.include?(dep.name) }
        breaks_in = @hops.find { |hop| limits.any? { |dep| !allows?(dep.requirement, hop) } }
        next unless breaks_in

        requires = limits.map { |dep| "#{dep.name} #{dep.requirement}" }.join(", ")
        { message: "#{spec.name} #{spec.version} requires #{requires}, so it doesn't install on Rails #{breaks_in}. Upgrade it to a release that allows #{breaks_in}, or replace it.",
          status: :failed, removed_in: breaks_in, fix_effort: :medium }
      end
    end

    # sqlite3 1.3 still installs next to Rails 6.0, but Rails refuses to load it as the adapter.
    def adapter_limits
      @specs.filter_map do |spec|
        breaks_in = @hops.find do |hop|
          requirement = @adapter_requirements.dig(hop, spec.name)
          requirement && !Gem::Requirement.new(*requirement).satisfied_by?(spec.version)
        end
        next unless breaks_in

        requirement = @adapter_requirements[breaks_in][spec.name].join(", ")
        { message: "#{spec.name} #{spec.version} doesn't load on Rails #{breaks_in}, which requires #{spec.name} #{requirement}. Upgrade it in the same step.",
          status: :failed, removed_in: breaks_in, fix_effort: :low }
      end
    end

    # A gem the app gets only through `rails` disappears on the hop where rails stops depending on it.
    # Still pulled in by the Gemfile or another gem (sass-rails needs sprockets-rails), it stays.
    def dropped_by_rails
      locked = @specs.map(&:name)
      kept = @direct + @specs.reject { |spec| spec.name == "rails" }.flat_map { |spec| spec.dependencies.map(&:name) }
      @hops.flat_map do |hop|
        @dropped_by_rails.fetch(hop, []).select { |name| locked.include?(name) && !kept.include?(name) }.map do |name|
          { message: "Rails #{hop} no longer depends on #{name}, and the Gemfile doesn't list it. Add gem \"#{name}\" to the Gemfile in the same step.",
            status: :failed, removed_in: hop, fix_effort: :low }
        end
      end
    end

    # Any patch release of the minor counts: `>= 7.0.1` allows 7.0.
    def allows?(requirement, minor)
      [minor, "#{minor}.99"].any? { |v| requirement.satisfied_by?(Gem::Version.new(v)) }
    end

    def curated
      locked = @specs.to_h { |spec| [spec.name, spec.version] }
      @entries.filter_map do |entry|
        version = locked[entry['name']]
        next unless version
        next if entry['fixed_in'] && version >= Gem::Version.new(entry['fixed_in'])

        files = usage(entry['pattern'])
        next if entry['only_if_used'] && files.empty?

        breaks_in = entry['breaks_in']
        blocks = @hops.include?(breaks_in) # every hop is past the current Rails
        message = "#{entry['name']} #{entry['fixed_in'] ? "#{version} " : ''}#{entry['message']}"
        if breaks_in && !blocks
          message += Gem::Version.new(breaks_in) <= Gem::Version.new(@hops.last) ?
            " It doesn't work from Rails #{breaks_in}, which this app is already on." :
            " It doesn't work from Rails #{breaks_in}, so plan the move before then."
        end
        message += " Used in #{files.size} #{files.size == 1 ? 'file' : 'files'}." if files

        { message: message, status: blocks ? :failed : :warning, removed_in: (breaks_in if blocks),
          details: ["Source: #{entry['source']}", *files], fix_effort: entry['fix_effort']&.to_sym }
      end
    end

    # Files matching the entry's pattern, nil when it has none.
    def usage(pattern)
      return unless pattern

      rule = { 'pattern' => pattern, 'message' => pattern }
      DeprecationAnalyzer.new(@project_path).scan_files([rule]).map { |hit| hit[:file] }.uniq.sort
    end
  end
end
