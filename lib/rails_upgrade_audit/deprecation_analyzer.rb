# lib/rails_upgrade_audit/deprecation_analyzer.rb
module RailsUpgradeAudit
  class DeprecationAnalyzer
    DATA_PATH = File.expand_path('../../database/deprecations.yml', __dir__)

    def initialize(root_path = Dir.pwd)
      @root_path = root_path
      @rules = YAML.load_file(DATA_PATH)
    end

    def run
      result = { title: "Deprecation Warnings", status: :passed, checks: [] }
      
      warnings = []

      @rules['deprecations'].each do |rule|
        regex = Regexp.new(rule['pattern'])
        warnings.concat(scan_files(regex, rule['message']))
      end

      if warnings.any?
        result[:status] = :warning
        warnings.each do |w|
          result[:checks] << { message: w, status: :warning }
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
