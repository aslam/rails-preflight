module RailsPreflight
  class SummaryCalculator
    # Explicit check[:kind] (:unknown, :tip) wins; otherwise failures block and warnings need fixing.
    KIND_BY_STATUS = { failed: :blocker, warning: :to_fix }.freeze
    LABELS = { blocker: "blocker", to_fix: "to fix", unknown: "couldn't check" }.freeze
    # Covered by the Ruby note on each upgrade step instead of "Before you start"
    STEP_SECTIONS = ["Rails Version", "Ruby Version"].freeze

    # hops: Rails minor versions to pass through, each { version:, min_ruby:, max_ruby: }
    # (see UpgradeAnalyzer#upgrade_hops); empty when already on the target. app_ruby: the app's Ruby version, if known.
    def initialize(results, target_rails = "Unknown", current_rails = nil, hops: nil, app_ruby: nil)
      @results = results
      @target_rails = target_rails
      @current_rails = current_rails
      @hops = hops || [{ version: target_rails }]
      @app_ruby = app_ruby
    end

    def calculate
      {
        blockers: findings(:blocker),
        to_fix: findings(:to_fix),
        unknowns: findings(:unknown),
        suggested_path: suggested_path
      }
    end

    private

    def kind(check)
      check[:kind] || KIND_BY_STATUS[check[:status]]
    end

    def findings(wanted)
      @results.flat_map do |section|
        section[:checks].select { |check| kind(check) == wanted }.map { |check| finding(section, check) }
      end
    end

    def finding(section, check)
      { section: section[:title], message: check[:message], occurrences: check.dig(:stats, :occurrences) }
    end

    # "Before you start" for general findings, then one step per Rails minor version,
    # since Rails recommends upgrading one minor version at a time.
    def suggested_path
      steps = []
      prep = preparation
      steps << { title: "Before you start", items: prep } if prep.any?

      from = @current_rails
      @hops.each do |hop|
        title = from ? "Rails #{from} → #{hop[:version]}" : "Upgrade to Rails #{hop[:version]}"
        steps << { title: title, items: [ruby_note(hop)] + step_findings(hop[:version]) }
        from = hop[:version]
      end
      steps
    end

    # Work per section that doesn't belong to a specific step, blocking sections first
    def preparation
      sections = @results.filter_map do |section|
        next if STEP_SECTIONS.include?(section[:title])
        counts = section[:checks].reject { |check| step_for(check) }.map { |check| kind(check) }.tally.slice(:blocker, :to_fix, :unknown)
        [section[:title], counts] if counts.any?
      end
      blocking, rest = sections.partition { |_, counts| counts[:blocker] }

      (blocking + rest).map do |title, counts|
        { section: title, message: counts.map { |k, n| "#{n} #{label(k, n)}" }.join(", ") }
      end
    end

    # An API removed in one of the step versions is fixed as part of that step
    def step_for(check)
      removed = check[:removed_in]&.to_s
      removed if removed && %i[blocker to_fix].include?(kind(check)) && @hops.any? { |hop| hop[:version] == removed }
    end

    def step_findings(version)
      @results.flat_map do |section|
        section[:checks].select { |check| step_for(check) == version }.map { |check| finding(section, check) }
      end
    end

    def ruby_note(hop)
      return { message: "Ruby requirements for Rails #{hop[:version]} are unknown" } unless hop[:min_ruby]

      range = "Ruby #{hop[:min_ruby]}–#{hop[:max_ruby].delete_suffix('.99')}"
      ruby = @app_ruby && Gem::Version.new(@app_ruby)
      message =
        if ruby.nil? then "Needs #{range}"
        elsif ruby < Gem::Version.new(hop[:min_ruby]) then "Needs #{range}: upgrade Ruby from #{@app_ruby} first"
        elsif ruby > Gem::Version.new(hop[:max_ruby]) then "Needs #{range}: Ruby #{@app_ruby} is newer than it supports"
        else "Needs #{range}: #{@app_ruby} works"
        end
      { message: message }
    end

    def label(kind, count)
      kind == :blocker && count > 1 ? "blockers" : LABELS[kind]
    end
  end
end
