# lib/rails_preflight/config_analyzer.rb
require_relative 'deprecation_analyzer'

module RailsPreflight
  class ConfigAnalyzer
    # `key: value` in YAML, key quoted or not, with the value up to a trailing comment.
    YAML_PAIR = /^\s*-?\s*["']?([\w-]+)["']?\s*:\s*(.*?)\s*(?:\s#.*)?$/
    # Values, unquoted, that hold nothing secret: ERB, aliases, anchors, flow collections, booleans, null, numbers.
    NOT_LITERAL = /\A(?:<%|[*&{\[]|(?:true|false|yes|no|null|~|-?\d+(?:\.\d+)?)\z)/i
    # Top-level sections whose values never reach production.
    LOCAL_ENVS = %w[development test].freeze
    SECRETS_REMOVED = "https://guides.rubyonrails.org/7_2_release_notes.html#railties-removals"

    def initialize(root_path = Dir.pwd, current_rails = nil, target_rails: nil)
      @root_path = root_path
      # load_defaults takes a minor version ("7.1"), so compare at that level
      @current_rails = Gem::Version.new(current_rails.to_s.split(".").first(2).join(".")) if current_rails
      @target_rails = Gem::Version.new(target_rails) if target_rails && Gem::Version.correct?(target_rails)
    end

    def run
      result = { title: "Configuration", status: :passed, checks: [], confidence: :high }

      app_config = File.join(@root_path, 'config', 'application.rb')
      if File.exist?(app_config)
        check_load_defaults(File.read(app_config), result[:checks])
      else
        result[:checks] << { message: "config/application.rb not found.", status: :warning, kind: :unknown }
      end

      check_committed_secrets(result[:checks])
      check_secrets_secret_key_base(result[:checks])

      if result[:checks].any?
        result[:status] = :warning
      else
        result[:checks] << { message: "No configuration issues found.", status: :passed }
      end

      result
    end

    private

    def check_load_defaults(content, checks)
      match = content.match(/^\s*config\.load_defaults\b\s*\(?\s*["']?(\d+\.\d+)?/)

      if match.nil?
        # load_defaults arrived in Rails 5.1
        return if @current_rails && @current_rails < Gem::Version.new("5.1")
        checks << { message: "config.load_defaults missing in application.rb. Without it, the app keeps legacy framework defaults unless each is set by hand.", status: :warning, fix_effort: :medium }
      elsif match[1] && @current_rails && Gem::Version.new(match[1]) < @current_rails
        message = "load_defaults #{match[1]} is behind Rails #{@current_rails}: framework defaults added after #{match[1]} are not enabled."
        pending = Dir.glob(File.join(@root_path, 'config', 'initializers', 'new_framework_defaults*.rb')).map { |f| File.basename(f) }
        message += " Found #{pending.join(', ')}, so enabling them looks in progress." if pending.any?
        checks << { message: message, status: :warning, fix_effort: :medium }
      end
    end

    # Secret-named keys with a literal value, outside the development and test sections. Shows the key, never the value.
    def check_committed_secrets(checks)
      hits = yaml_pairs(Dir.glob(File.join(@root_path, "config", "**", "*.{yml,yml.erb}")).reject { |file| file.include?("/locales/") })
             .select { |_, _, section, key, value| key.match?(DeprecationAnalyzer::SECRET_NAME) && literal?(value) && !LOCAL_ENVS.include?(section) }
      return if hits.empty?

      them = hits.one? ? "it" : "them"
      checks << { message: "#{hits.one? ? 'A secret is' : "#{hits.size} secrets are"} committed in config YAML, where anyone with the repository can read #{them}. Rotate #{them}, and read #{them} from credentials or ENV instead.",
                  status: :warning, fix_effort: :medium, files: hits.map { |file, line, _, key| { file: file, line: line, snippet: "#{key}: [hidden]" } } }
    end

    # Rails 7.2 stops reading config/secrets.yml, so a production secret_key_base set there is lost; one read from
    # ENV["SECRET_KEY_BASE"] still works, since 7.2 reads that variable itself.
    def check_secrets_secret_key_base(checks)
      return if @current_rails && @current_rails >= Gem::Version.new("7.2")

      hit = yaml_pairs([File.join(@root_path, "config", "secrets.yml")]).find do |_, _, section, key, value|
        %w[production shared].include?(section) && key == "secret_key_base" && !value.empty? && !value.match?(/ENV(?:\[|\.fetch\(\s*)["']SECRET_KEY_BASE["']/)
      end
      return unless hit

      checks << { message: "'config/secrets.yml' sets 'secret_key_base' for production, and Rails 7.2 no longer reads 'config/secrets.yml'. Move the same value to credentials or 'SECRET_KEY_BASE' first: a new one invalidates sessions and signed cookies.",
                  status: @target_rails && @target_rails >= Gem::Version.new("7.2") ? :failed : :warning, removed_in: "7.2", fix_effort: :medium,
                  source: SECRETS_REMOVED, files: [{ file: hit[0], line: hit[1], snippet: "secret_key_base: [hidden]" }] }
    end

    def literal?(value)
      value = value.sub(/\A(["'])(.*)\1\z/, '\2')
      !value.empty? && !value.match?(NOT_LITERAL)
    end

    # [file, line, top-level section, key, value] for each `key: value` line in the files that exist.
    def yaml_pairs(files)
      files.select { |file| File.file?(file) }.sort.flat_map do |file|
        section = nil
        File.foreach(file, encoding: "UTF-8").with_index(1).filter_map do |line, number|
          section = $1 if line =~ /^([\w-]+):/
          next unless (pair = line.match(YAML_PAIR))
          [file.delete_prefix(File.join(@root_path, "")), number, section, pair[1], pair[2]]
        end
      end
    end
  end
end
