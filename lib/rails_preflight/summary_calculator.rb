module RailsPreflight
  class SummaryCalculator
    # Explicit check[:kind] (:unknown, :tip) wins; otherwise failures block and warnings need fixing.
    KIND_BY_STATUS = { failed: :blocker, warning: :to_fix }.freeze
    LABELS = { broken: "already broken", blocker: "blocker", to_fix: "to fix", unknown: "couldn't check" }.freeze
    # Covered by the Ruby note on each upgrade step instead of "Before you start"
    STEP_SECTIONS = ["Rails Version", "Ruby Version"].freeze

    # hops: Rails minor versions to pass through, each { version:, min_ruby:, max_ruby: }
    # (see UpgradeAnalyzer#upgrade_hops); empty when already on the target. app_ruby: the app's Ruby version, if known.
    # current_max_ruby: newest Ruby the current Rails supports, if known.
    def initialize(results, target_rails = "Unknown", current_rails = nil, hops: nil, app_ruby: nil, current_max_ruby: nil)
      @results = results
      @target_rails = target_rails
      @current_rails = current_rails
      @hops = hops || [{ version: target_rails }]
      @app_ruby = app_ruby
      @current_max_ruby = current_max_ruby
    end

    def calculate
      {
        broken: findings(:broken),
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
      ruby = @app_ruby # the Ruby the app runs at each step, after the upgrades suggested so far
      max_now = @current_max_ruby
      @hops.each do |hop|
        title = from ? "Rails #{from} → #{hop[:version]}" : "Upgrade to Rails #{hop[:version]}"
        note, ruby = ruby_note(hop, ruby, max_now)
        steps << { title: title, items: [note] + step_findings(hop[:version]) }
        from = hop[:version]
        max_now = hop[:max_ruby]
      end
      steps
    end

    # Work per section that doesn't belong to a specific step, blocking sections first
    def preparation
      sections = @results.filter_map do |section|
        next if STEP_SECTIONS.include?(section[:title])
        counts = section[:checks].reject { |check| step_for(check) }.map { |check| kind(check) }.tally.slice(:broken, :blocker, :to_fix, :unknown)
        [section[:title], counts] if counts.any?
      end
      blocking, rest = sections.partition { |_, counts| counts[:broken] || counts[:blocker] }

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

    # [note, Ruby after this step]. A Ruby too old for the step is upgraded on the Rails before it, to the newest
    # Ruby both support, so later steps need as few Ruby upgrades as possible.
    def ruby_note(hop, ruby, max_now)
      return [{ message: "Ruby requirements for Rails #{hop[:version]} are unknown" }, ruby] unless hop[:min_ruby]

      range = "Ruby #{hop[:min_ruby]}–#{short(hop[:max_ruby])}"
      version = ruby && Gem::Version.new(ruby)
      message =
        if version.nil? then "Needs #{range}"
        elsif version < Gem::Version.new(hop[:min_ruby])
          upgraded = [max_now, hop[:max_ruby]].compact.min_by { |v| Gem::Version.new(v) }
          from, ruby = ruby, upgraded
          "Needs #{range}: upgrade Ruby from #{short(from)} to #{short(upgraded)} first"
        elsif version > Gem::Version.new(hop[:max_ruby]) then "Needs #{range}: Ruby #{short(ruby)} is newer than it supports"
        else "Needs #{range}: #{short(ruby)} works"
        end
      [{ message: message }, ruby]
    end

    def short(ruby)
      ruby.delete_suffix(".99")
    end

    def label(kind, count)
      kind == :blocker && count > 1 ? "blockers" : LABELS[kind]
    end
  end
end
