# lib/rails_preflight/database_analyzer.rb

module RailsPreflight
  class DatabaseAnalyzer
    def initialize(project_path, rules = [])
      @schema_path = File.join(project_path, "db/schema.rb")
      @structure_path = File.join(project_path, "db/structure.sql")
      @rules = rules || []
      @warnings = []
    end

    def run
      # Pattern-based, so medium confidence
      result = { title: "Database Schema", status: :passed, checks: [], confidence: :medium }

      unless File.exist?(@schema_path)
        result[:status] = :warning
        # ponytail: structure.sql is only noted; reading its CREATE TABLEs is on the roadmap.
        message = if File.exist?(@structure_path)
                    "The schema is in db/structure.sql, which isn't read yet, so the schema checks (table charset, integer primary keys) were skipped. Check those in the SQL by hand."
                  else
                    "No db/schema.rb found. Skipping database checks."
                  end
        result[:checks] << { message: message, status: :warning, kind: :unknown }
        return result
      end

      if @rules.empty?
        result[:checks] << { message: "No database checks apply to this target Rails version.", status: :passed }
        return result
      end

      content = File.read(@schema_path)
      scan_schema(content)

      if @warnings.any?
        result[:status] = @warnings.any? { |w| w[:severity] == 'critical' } ? :failed : :warning
        @warnings.each do |w|
           result[:checks] << {
             message: w[:message],
             status: w[:severity] == 'critical' ? :failed : :warning
           }
        end
      end

      result
    end

    private

    def scan_schema(content)
      @rules.each do |rule|
        pattern = Regexp.new(rule['pattern'])
        if content.match?(pattern)
          @warnings << {
            type: rule['name'],
            message: rule['message'],
            severity: rule['type']
          }
        end
      end
    end
  end
end
