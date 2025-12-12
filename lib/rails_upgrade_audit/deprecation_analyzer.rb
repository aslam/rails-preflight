# lib/rails_upgrade_audit/deprecation_analyzer.rb
module RailsUpgradeAudit
  class DeprecationAnalyzer
    DATA_PATH = File.expand_path('../../database/deprecations.yml', __dir__)

    def initialize(root_path = Dir.pwd)
      @root_path = root_path
      @rules = YAML.load_file(DATA_PATH)
    end

    def run
      puts "\n[3/X] Checking for Deprecations..."
      
      warnings = []

      @rules['deprecations'].each do |rule|
        regex = Regexp.new(rule['pattern'])
        warnings.concat(scan_files(regex, rule['message']))
      end

      if warnings.any?
        puts "\n⚠️  DEPRECATION WARNINGS:"
        warnings.each { |w| puts w }
      else
        puts "✅ No obvious deprecated patterns found (UpgradeAudit is static, check logs too!)"
      end
    end

    private

    def scan_files(regex, message)
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
            found << "#{message}\n   Example: #{relative_path}:#{line_num}: #{line.strip}"
          end
        end
      end
      found
    end
  end
end
