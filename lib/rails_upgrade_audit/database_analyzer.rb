# lib/rails_upgrade_audit/database_analyzer.rb

module RailsUpgradeAudit
  class DatabaseAnalyzer
    def initialize(project_path, rules = [])
      @schema_path = File.join(project_path, "db/schema.rb")
      @rules = rules || []
      @warnings = []
    end

    def run
      puts "\n[5/X] Scanning Database Schema..."
      
      unless File.exist?(@schema_path)
        puts "⚠️  No db/schema.rb found. Skipping database checks."
        return
      end

      if @rules.empty?
        puts "✅ No database specific rules found for this Rails version."
        return
      end

      content = File.read(@schema_path)
      scan_schema(content)
      output_results
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

    def output_results
      if @warnings.any?
        puts "\n📉 DATABASE SCHEMA RISKS DETECTED:"
        @warnings.each do |w|
          icon = w[:severity] == 'critical' ? '🔴 CRITICAL:' : '⚠️ '
          puts "\n#{icon} #{w[:message]}"
        end
      else
        puts "✅ Database schema looks healthy according to version rules."
      end
    end
  end
end