module RailsPreflight
  require 'pathname'
  class DeprecationAnalyzer
    DATA_PATH = File.expand_path('../../database/deprecations.yml', __dir__)
    SCAN_DIRS = %w[app config db lib test spec].freeze
    SCAN_EXTS = %w[.rb .erb .rake .haml .slim].freeze
    # Lines that never run, by file type: [line comment, silent comment]. A silent comment hides the lines indented
    # under it too (HAML `-#`, Slim `/`); an HTML comment (HAML `/`, Slim `/!` or `/[if IE]`) is text, but the lines
    # under it still render and run. In templates `#main` is an element id, not a comment.
    COMMENTS = {
      '.haml' => [%r{\A/}, /\A-#/],
      '.slim' => [%r{\A/[!\[]}, %r{\A/(?![!\[])}]
    }.freeze
    RUBY_COMMENT = [/\A(?:#|<%#)/, nil].freeze
    # A rule runs on the kinds of files its `files:` lists, code by default.
    # scripts: where rake tasks get called from outside Ruby code. yaml: the app's own config files.
    FILE_GLOBS = {
      'scripts' => %w[bin/* script/**/* Procfile* Makefile Dockerfile* *.sh .github/workflows/*.{yml,yaml}
                      .circleci/config.yml .gitlab-ci.yml .travis.yml],
      'yaml' => %w[config/**/*.yml config/**/*.yml.erb]
    }.freeze
    # Snippets go into a report people print and share: on a line that names a secret, values are hidden.
    SECRET_NAME = /secret|token|passw(?:or)?d|api_?key|access_?key|private_?key|credential/i

    def initialize(root_path = Dir.pwd, database_path = DATA_PATH, target_rails: nil, current_rails: nil)
      @root_path = root_path
      @rules = YAML.load_file(database_path)
      @target_rails = target_rails
      @current_rails = current_rails
    end

    def run
      result = { title: "Deprecation Warnings", status: :passed, checks: [], confidence: :medium }

      # `unless_gem:` names a gem that keeps the API working (record_tag_helper keeps div_for).
      warnings = scan_files(@rules['deprecations'].reject { |rule| rule['unless_gem'] && locked?(rule['unless_gem']) })

      if warnings.any?
        # Group warnings by message
        grouped_warnings = warnings.group_by { |w| w[:message] }
        
        grouped_warnings.each do |message, occurrences|
          rule = occurrences.first
          info = rule[:severity].to_s.downcase == "info"
          # An API this upgrade removes blocks it; one removed before the current Rails is already broken
          # (or dead code); otherwise it's a warning to fix.
          removed_in = rule[:removed_in]
          status = info ? :passed : (removed_by_target?(removed_in) || already_removed?(removed_in) ? :failed : :warning)

          result[:checks] << {
            message: message,
            status: status,
            kind: (:tip if info) || (:broken if already_removed?(removed_in)),
            rule: rule[:rule],
            removed_in: removed_in,
            fix_effort: (rule[:fix_effort] || "low").to_sym,
            confidence: rule[:confidence]&.downcase&.to_sym,
            source: rule[:guide_link],
            files: occurrences.map { |hit| hit.slice(:file, :line, :snippet, :test) }
          }
        end

        statuses = result[:checks].map { |c| c[:status] }
        result[:status] = statuses.include?(:failed) ? :failed : (statuses.include?(:warning) ? :warning : :passed)
      else
        result[:checks] << { message: "No obvious deprecated patterns found (this scan is static; check your deprecation logs too).", status: :passed }
      end
      
      # Rubocop Advisory Check
      if check_rubocop_rails
        result[:checks] << { 
          message: "rubocop-rails is installed. Run `bundle exec rubocop -a` to auto-fix more deprecations.",
          status: :passed 
        }
      else
        result[:checks] << { 
          message: "Install rubocop-rails. It can auto-fix many deprecations this tool only detects.",
          status: :passed,
          kind: :tip
        }
      end

      result
    end

    # One pass over the files, every rule tested per line: a rule costs a regex, not a re-read.
    def scan_files(rules)
      found = []
      compiled = rules.map { |rule| [Regexp.new(rule['pattern']), rule] }

      files = Dir.glob(File.join(@root_path, "{#{SCAN_DIRS.join(',')}}/**/*")).select { |file| SCAN_EXTS.include?(File.extname(file)) }.to_h { |file| [file, 'code'] }
      FILE_GLOBS.each do |kind, globs|
        Dir.glob(globs.map { |glob| File.join(@root_path, glob) }).each { |file| files[file] ||= kind }
      end

      files.each do |file, kind|
        next if File.directory?(file)

        relative_path = Pathname.new(file).relative_path_from(Pathname.new(@root_path)).to_s
        test = relative_path.start_with?('test/', 'spec/')

        under = ->(paths) { paths.any? { |path| relative_path == path || relative_path.start_with?("#{path}/") } }
        # A rule with `paths:` only applies under those directories or to those files.
        applicable = compiled.select do |_regex, rule|
          rule.fetch('files', ['code']).include?(kind) && (rule['paths'].nil? || under.(rule['paths']))
        end
        next if applicable.empty?
        content = File.read(file)
        # Only `x.errors` counts under `needs_receiver_in:` (a bare `errors` in a helper or view is a local), and in a
        # file that assigns `errors` or takes it as a parameter (`skip_bare_if_local:`), where the bare name is that local.
        # ponytail: file-wide, so a model with an `errors` local in one method loses bare hits in the others.
        needs_receiver = applicable.select do |_regex, rule|
          (rule['needs_receiver_in'] && under.(rule['needs_receiver_in'])) ||
            (rule['skip_bare_if_local'] && local?(content, rule['skip_bare_if_local']))
        end.map(&:last)

        line_comment, silent_comment = COMMENTS.fetch(File.extname(file), RUBY_COMMENT)
        silenced = nil # indent of the silent comment the current lines sit under
        content.each_line.with_index(1) do |line, line_num|
          indent = line[/\A[ \t]*/].size
          next if silenced && (line.strip.empty? || indent > silenced)

          silenced = nil
          code = line.lstrip
          if silent_comment&.match?(code)
            silenced = indent
            next
          end
          # Skip comments and method definitions (e.g. "def update_attributes") to avoid false positives
          next if line_comment.match?(code) || code.start_with?("def ")

          applicable.each do |regex, rule|
            next unless (match = regex.match(line))
            next if needs_receiver.include?(rule) && !match.pre_match.end_with?(".")
            # `respond_to?(:x)` or `try(:x)` checks for the API, it doesn't use it; the line still counts if it uses it too.
            next if match.pre_match.match?(/(?:respond_to\?|try)\(\s*:\z/) && line.scan(regex).size == 1

            found << {
              message: rule['message'],
              rule: rule['id'],
              file: relative_path,
              line: line_num,
              test: test,
              snippet: redact(line.strip),
              confidence: rule['confidence'],
              guide_link: rule['guide_link'],
              removed_in: rule['removed_in'],
              severity: rule['severity'],
              fix_effort: rule['fix_effort']
            }
          end
        end
      end
      found
    end

    private

    # Quoted strings, and plain `name: value` / `NAME=value` values (YAML, shell, CI config), become [hidden].
    # ponytail: over-hides (ENV["SECRET_TOKEN"] loses its name too); the file and line still point to it.
    def redact(line)
      return line unless line.match?(SECRET_NAME)

      line.gsub(/(["'])(?:\\.|(?!\1).)*\1/) { "#{$1}[hidden]#{$1}" }
          .gsub(/((?:#{SECRET_NAME.source})\w*\s*(?:=>|[:=])\s*)[^"'\s#,][^#,]*?(?=\s*(?:#|,|$))/i) { "#{$1}[hidden]" }
    end

    # `name = ...`, `name ||= ...`, a block parameter (`do |x, name|`) or a method parameter.
    def local?(content, name)
      # [ \t], not \s: each part stays on one line (`def valid?` then `errors` on the next isn't a parameter).
      content.match?(/(?<![.@\w])#{name}[ \t]*(?:\|\|)?=(?![=~>])|(?:\bdo|\{)[ \t]*\|[\w \t,*&]*\b#{name}\b[\w \t,*&]*\||
                      ^[ \t]*def[ \t]+(?:self\.)?\w+[!?]?(?:[ \t]*\([^)\n]*\b#{name}\b|[ \t]+[^(=;\n]*\b#{name}\b)/x)
    end

    # Removed at or before the current version: the app already runs without it.
    def already_removed?(removed_in)
      removed_in && @current_rails && Gem::Version.new(removed_in.to_s) <= Gem::Version.new(@current_rails)
    end

    # Removed after the current version and by the target: this upgrade breaks it.
    def removed_by_target?(removed_in)
      return false unless removed_in && @target_rails
      removed = Gem::Version.new(removed_in.to_s)
      removed <= Gem::Version.new(@target_rails) && (@current_rails.nil? || removed > Gem::Version.new(@current_rails))
    end

    def check_rubocop_rails
      locked?("rubocop-rails")
    end

    def locked?(gem)
      @lockfile ||= File.exist?(File.join(@root_path, "Gemfile.lock")) ? File.read(File.join(@root_path, "Gemfile.lock")) : ""
      @lockfile.match?(/^ {4}#{Regexp.escape(gem)} \(/)
    end

  end
end
