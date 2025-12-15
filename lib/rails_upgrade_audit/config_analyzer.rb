# lib/rails_upgrade_audit/config_analyzer.rb
module RailsUpgradeAudit
  class ConfigAnalyzer
    def initialize(root_path = Dir.pwd)
      @root_path = root_path
    end

    def run
      result = { title: "Configuration", status: :passed, checks: [], confidence: :high }
      
      issues = []

      # 1. Check load_defaults
      app_config = File.join(@root_path, 'config', 'application.rb')
      if File.exist?(app_config)
        content = File.read(app_config)
        unless content.match?(/^\s*config\.load_defaults/)
          issues << "⚠️  CONFIG: 'config.load_defaults' missing in application.rb. Crucial for Rails 5+ upgrades."
        end
      else
        issues << "❓  CONFIG: config/application.rb not found."
      end

      # 2. Check for new_framework_defaults
      # usually found as config/initializers/new_framework_defaults_X_Y.rb
      if Dir.glob(File.join(@root_path, 'config', 'initializers', 'new_framework_defaults*.rb')).empty?
        issues << "ℹ️  CONFIG: No 'new_framework_defaults' initializer found. Make sure you run 'rails app:update'."
      end

      if issues.any?
        result[:status] = :warning
        issues.each do |issue| 
            # Parse prefix emoji for status if possible, or defaulting to warning
            status = issue.start_with?("❓") ? :failed : :warning
            result[:checks] << { message: issue, status: status }
        end
      else
        result[:checks] << { message: "Configuration looks baseline sane.", status: :passed }
      end
      
      result
    end
  end
end
