module RailsPreflight
  require 'pathname'
  class DeprecationAnalyzer
    DATA_PATH = File.expand_path('../../database/deprecations.yml', __dir__)
    SCAN_DIRS = %w[app config lib test spec].freeze
    SCAN_EXTS = %w[.rb .erb].freeze

    def initialize(root_path = Dir.pwd, database_path = DATA_PATH, target_rails: nil, current_rails: nil)
      @root_path = root_path
      @rules = YAML.load_file(database_path)
      @target_rails = target_rails
      @current_rails = current_rails
    end

    def run
      result = { title: "Deprecation Warnings", status: :passed, checks: [], confidence: :medium }

      warnings = scan_files(@rules['deprecations'])

      if warnings.any?
        # Group warnings by message
        grouped_warnings = warnings.group_by { |w| w[:message] }
        
        grouped_warnings.each do |message, occurrences|
          # Calculate stats
          files_affected = occurrences.map { |w| w[:file] }.uniq.count
          models_affected = occurrences.count { |w| w[:file].include?('app/models') }
          controllers_affected = occurrences.count { |w| w[:file].include?('app/controllers') }
          
          # Use the severity of the first occurrence (rule based)
          severity = occurrences.first[:severity] || "Warning"
          fix_effort = occurrences.first[:fix_effort] || "low"
          info = severity.to_s.downcase == "info"
          # An API this upgrade removes blocks it; otherwise it's a warning to fix.
          status = info ? :passed : (removed_by_target?(occurrences.first[:removed_in]) ? :failed : :warning)

          result[:checks] << {
            message: message,
            status: status,
            kind: (:tip if info),
            grouped: true,
            guide_link: occurrences.first[:guide_link],
            removed_in: occurrences.first[:removed_in],
            stats: {
              occurrences: occurrences.count,
              occurrences_app: occurrences.count { |w| !w[:is_test] },
              occurrences_test: occurrences.count { |w| w[:is_test] },
              files: files_affected,
              models: models_affected,
              controllers: controllers_affected,
              severity: severity,
              fix_effort: fix_effort
            },
            details: occurrences # Pass all occurrences for the detail view
          }
        end

        statuses = result[:checks].map { |c| c[:status] }
        result[:status] = statuses.include?(:failed) ? :failed : (statuses.include?(:warning) ? :warning : :passed)
      else
        result[:checks] << { message: "No obvious deprecated patterns found (this scan is static; check your deprecation logs too).", status: :passed }
      end
      
      # Rubocop Advisory Check
      if check_rubocop_rails
        result[:checks] << { 
          message: "rubocop-rails is installed. Run `bundle exec rubocop -a` to auto-fix more deprecations.",
          status: :passed 
        }
      else
        result[:checks] << { 
          message: "Install rubocop-rails. It can auto-fix many deprecations this tool only detects.",
          status: :passed,
          kind: :tip
        }
      end

      result
    end

    private

    # Removed after the current version and by the target: this upgrade breaks it.
    def removed_by_target?(removed_in)
      return false unless removed_in && @target_rails
      removed = Gem::Version.new(removed_in.to_s)
      removed <= Gem::Version.new(@target_rails) && (@current_rails.nil? || removed > Gem::Version.new(@current_rails))
    end

    def check_rubocop_rails
      lockfile_path = File.join(@root_path, "Gemfile.lock")
      return false unless File.exist?(lockfile_path)
      
      content = File.read(lockfile_path)
      content.include?("rubocop-rails")
    end

    # One pass over the files, every rule tested per line: a rule costs a regex, not a re-read.
    def scan_files(rules)
      found = []
      compiled = rules.map { |rule| [Regexp.new(rule['pattern']), rule] }

      Dir.glob(File.join(@root_path, "{#{SCAN_DIRS.join(',')}}/**/*")).each do |file|
        next if File.directory?(file)
        next unless SCAN_EXTS.include?(File.extname(file))

        relative_path = Pathname.new(file).relative_path_from(Pathname.new(@root_path)).to_s
        top_dir = relative_path.split('/').first
        is_test = relative_path.start_with?('test/', 'spec/')

        # A rule with `paths:` only applies under those directories.
        applicable = compiled.reject { |_regex, rule| rule['paths'] && !rule['paths'].include?(top_dir) }
        next if applicable.empty?

        File.foreach(file).with_index(1) do |line, line_num|
          # Skip comments and method definitions (e.g. "def update_attributes") to avoid false positives
          next if line.lstrip.start_with?("#", "def ", "<%#")

          applicable.each do |regex, rule|
            next unless line.match?(regex)

            found << {
              message: rule['message'],
              file: relative_path,
              line: line_num,
              is_test: is_test,
              snippet: line.strip,
              confidence: rule['confidence'] || "Unknown",
              guide_link: rule['guide_link'],
              recategorization: rule['recategorization'],
              removed_in: rule['removed_in'],
              severity: rule['severity'],
              fix_effort: rule['fix_effort']
            }
          end
        end
      end
      found
    end
  end
end
