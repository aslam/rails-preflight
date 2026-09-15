# lib/rails_preflight/config_analyzer.rb
module RailsPreflight
  class ConfigAnalyzer
    def initialize(root_path = Dir.pwd, current_rails = nil)
      @root_path = root_path
      # load_defaults takes a minor version ("7.1"), so compare at that level
      @current_rails = Gem::Version.new(current_rails.to_s.split(".").first(2).join(".")) if current_rails
    end

    def run
      result = { title: "Configuration", status: :passed, checks: [], confidence: :high }

      app_config = File.join(@root_path, 'config', 'application.rb')
      if File.exist?(app_config)
        check_load_defaults(File.read(app_config), result[:checks])
      else
        result[:checks] << { message: "CONFIG: config/application.rb not found.", status: :failed }
      end

      if result[:checks].any?
        result[:status] = :warning
      else
        result[:checks] << { message: "Configuration looks baseline sane.", status: :passed }
      end

      result
    end

    private

    def check_load_defaults(content, checks)
      match = content.match(/^\s*config\.load_defaults\b\s*\(?\s*["']?(\d+\.\d+)?/)

      if match.nil?
        # load_defaults arrived in Rails 5.1
        return if @current_rails && @current_rails < Gem::Version.new("5.1")
        checks << { message: "CONFIG: 'config.load_defaults' missing in application.rb. Without it, the app keeps legacy framework defaults unless each is set by hand.", status: :warning, fix_effort: :medium }
      elsif match[1] && @current_rails && Gem::Version.new(match[1]) < @current_rails
        message = "CONFIG: load_defaults #{match[1]} is behind Rails #{@current_rails}: framework defaults added after #{match[1]} are not enabled."
        pending = Dir.glob(File.join(@root_path, 'config', 'initializers', 'new_framework_defaults*.rb')).map { |f| File.basename(f) }
        message += " Found #{pending.join(', ')}, so enabling them looks in progress." if pending.any?
        checks << { message: message, status: :warning, fix_effort: :medium }
      end
    end
  end
end
