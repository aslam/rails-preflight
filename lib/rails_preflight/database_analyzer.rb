# lib/rails_preflight/database_analyzer.rb

module RailsPreflight
  class DatabaseAnalyzer
    def initialize(project_path, rules = [])
      @schema_path = File.join(project_path, "db/schema.rb")
      @rules = rules || []
      @warnings = []
    end

    def run
      result = { title: "Database Schema", status: :passed, checks: [], confidence: :high }
      
      unless File.exist?(@schema_path)
        result[:status] = :warning
        result[:checks] << { message: "No db/schema.rb found. Skipping database checks.", status: :warning }
        return result
      end

      if @rules.empty?
        # No rules means we didn't find anything specific to check, so it passes "vacuously" or we can say info.
        # But for consistency let's just return empty passed.
        return result
      end

      content = File.read(@schema_path)
      scan_schema(content)
      
      if @warnings.any?
        result[:status] = @warnings.any? { |w| w[:severity] == 'critical' } ? :failed : :warning
        @warnings.each do |w|
           result[:checks] << {
             message: w[:message], 
             status: w[:severity] == 'critical' ? :failed : :warning,
             details: w[:type]
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

    # output_results method removed as it is no longer used

  end
end
