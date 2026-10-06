module RailsPreflight
  # Gems that stop working, or are on their way out, across the upgrade: Rails limits their locked versions
  # declare in Gemfile.lock, plus the curated list in database/gems.yml for limits only a README states.
  class GemAnalyzer
    DATA_PATH = File.expand_path('../../database/gems.yml', __dir__)
    RAILS_GEMS = %w[rails railties actioncable actionmailbox actionmailer actionpack actiontext actionview
                    activejob activemodel activerecord activestorage activesupport].freeze

    # specs: Gemfile.lock specs. hops: the Rails minors the upgrade passes through, after the current one, ending at the target.
    def initialize(project_path, specs, hops:, database_path: DATA_PATH)
      @project_path = project_path
      @specs = specs
      @hops = hops
      @entries = YAML.load_file(database_path).fetch('gems', [])
    end

    def run
      result = { title: "Gem Compatibility", status: :passed, checks: [], confidence: :medium }
      return result if @hops.empty? # already on the target
      result[:checks].concat(locked_limits, curated)

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

    # Any patch release of the minor counts: `>= 7.0.1` allows 7.0.
    def allows?(requirement, minor)
      [minor, "#{minor}.99"].any? { |v| requirement.satisfied_by?(Gem::Version.new(v)) }
    end

    def curated
      names = @specs.map(&:name)
      @entries.select { |entry| names.include?(entry['name']) }.map do |entry|
        breaks_in = entry['breaks_in']
        blocks = @hops.include?(breaks_in) # every hop is past the current Rails
        message = "#{entry['name']} #{entry['message']}"
        if breaks_in && !blocks
          message += Gem::Version.new(breaks_in) <= Gem::Version.new(@hops.last) ?
            " It doesn't work from Rails #{breaks_in}, which this app is already on." :
            " It doesn't work from Rails #{breaks_in}, so plan the move before then."
        end
        files = usage(entry['pattern'])
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
