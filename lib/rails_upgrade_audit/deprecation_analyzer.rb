module RailsUpgradeAudit
  require 'pathname'
  class DeprecationAnalyzer
    DATA_PATH = File.expand_path('../../database/deprecations.yml', __dir__)

    def initialize(root_path = Dir.pwd, database_path = DATA_PATH)
      @root_path = root_path
      @rules = YAML.load_file(database_path)
    end

    def run
      result = { title: "Deprecation Warnings", status: :passed, checks: [] }
      
      warnings = []

      @rules['deprecations'].each do |rule|
        regex = Regexp.new(rule['pattern'])
        # Pass the whole rule to scan_files
        warnings.concat(scan_files(regex, rule))
      end

      if warnings.any?
        result[:status] = :warning
        
        # Group warnings by message
        grouped_warnings = warnings.group_by { |w| w[:message] }
        
        grouped_warnings.each do |message, occurrences|
          # Calculate stats
          files_affected = occurrences.map { |w| w[:file] }.uniq.count
          models_affected = occurrences.count { |w| w[:file].include?('app/models') }
          controllers_affected = occurrences.count { |w| w[:file].include?('app/controllers') }
          
          # Use the severity of the first occurrence (rule based)
          severity = occurrences.first[:severity] || "Warning"
          
          result[:checks] << {
            message: message,
            status: :warning,
            grouped: true,
            stats: {
              occurrences: occurrences.count,
              files: files_affected,
              models: models_affected,
              controllers: controllers_affected,
              severity: severity
            },
            details: occurrences # Pass all occurrences for the detail view
          }
        end
      else
        result[:checks] << { message: "No obvious deprecated patterns found (UpgradeAudit is static, check logs too!)", status: :passed }
      end
      
      # Rubocop Advisory Check
      if check_rubocop_rails
        result[:checks] << { 
          message: "✅ Action: `rubocop-rails` detected. Run `bundle exec rubocop -a` to find and fix more issues.",
          status: :passed 
        }
      else
        result[:checks] << { 
          message: "💡 Recommendation: Install `rubocop-rails` gem. It can auto-fix many deprecations that this tool cannot.",
          status: :warning 
        }
      end

      result
    end

    private

    def check_rubocop_rails
      lockfile_path = File.join(@root_path, "Gemfile.lock")
      return false unless File.exist?(lockfile_path)
      
      content = File.read(lockfile_path)
      content.include?("rubocop-rails")
    end

    def scan_files(regex, rule)
      found = []
      # Naive generic scan of app/ and lib/
      target_files = Dir.glob(File.join(@root_path, "{app,lib,test,spec}/**/*"))
      
      target_files.each do |file|
        next if File.directory?(file)
        next unless file.end_with?('.rb')

        content = File.read(file)
        content.each_line.with_index(1) do |line, line_num|
          if line.match?(regex)
            relative_path = Pathname.new(file).relative_path_from(Pathname.new(@root_path))
            
            found << {
              message: rule['message'],
              file: relative_path.to_s,
              line: line_num,
              snippet: line.strip,
              confidence: rule['confidence'] || "Unknown",
              guide_link: rule['guide_link'],
              recategorization: rule['recategorization'],
              severity: rule['severity']
            }
          end
        end
      end
      found
    end
  end
end
