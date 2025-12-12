# lib/rails_upgrade_audit/deprecation_analyzer.rb
module RailsUpgradeAudit
  class DeprecationAnalyzer
    def initialize(root_path = Dir.pwd)
      @root_path = root_path
    end

    def run
      puts "\n[3/X] Checking for Deprecations..."
      
      warnings = []

      # 1. update_attributes (Removed in Rails 6.1)
      warnings.concat(scan_files(/update_attributes!?/, "DEPRECATION: 'update_attributes' was removed in Rails 6.1. Use 'update' instead."))

      # 2. success? on controller tests (Deprecated in Rails 5, removed later for kwargs)
      # This is a bit looser, usually checking strict kwargs in tests is the issue, but success? is a good proxy for old tests
      warnings.concat(scan_files(/assert_response :success/, "INFO: Verify controller tests use kwargs (e.g. get :index, params: { ... })"))

      # 3. ActiveRecord::Base.errors (Change in behavior around 6.1)
      # warnings.concat(scan_files(/errors\[:/, "POTENTIAL: Accessing errors as hash (errors[:field]) changed behavior in 6.1."))

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
