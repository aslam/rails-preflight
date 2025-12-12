# lib/rails_upgrade_audit/config_analyzer.rb
module RailsUpgradeAudit
  class ConfigAnalyzer
    def initialize(root_path = Dir.pwd)
      @root_path = root_path
    end

    def run
      puts "\n[4/X] Checking Configuration..."

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
        puts "\n🛠️  CONFIGURATION ISSUES:"
        issues.each { |i| puts i }
      else
        puts "✅ Configuration looks baseline sane."
      end
    end
  end
end
