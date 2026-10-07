module RailsPreflight
  class SummaryCalculator
    # Explicit check[:kind] (:broken, :unknown, :tip) wins; otherwise failures block and warnings need fixing.
    KIND_BY_STATUS = { failed: :blocker, warning: :to_fix }.freeze
    # Order of the rows in a step card
    KINDS = %i[broken blocker to_fix tip].freeze

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

    # Counts by kind, then every finding placed once: before the first step, in the step that removes it,
    # ahead of the target (removed by a later Rails), or under what the report couldn't check.
    def calculate
      shown = entries.reject { |entry| entry[:kind] == :unknown }
      in_steps, rest = shown.partition { |entry| step_for(entry) }
      ahead, before = rest.partition { |entry| ahead?(entry) }
      {
        broken: findings(:broken),
        blockers: findings(:blocker),
        to_fix: findings(:to_fix),
        unknowns: findings(:unknown),
        before: in_order(before),
        steps: steps(in_steps),
        ahead: ahead.group_by { |entry| entry[:removed_in].to_s }.sort_by { |version, _| Gem::Version.new(version) }.to_h,
        cant_see: entries.select { |entry| entry[:kind] == :unknown }
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

    # Every check that isn't a plain pass, with its section and kind.
    def entries
      @entries ||= @results.flat_map do |section|
        section[:checks].filter_map { |check| check.merge(section: section[:title], kind: kind(check)) if kind(check) }
      end
    end

    def in_order(entries)
      entries.sort_by.with_index { |entry, i| [KINDS.index(entry[:kind]) || KINDS.size, i] }
    end

    # One step per Rails minor version, since Rails recommends upgrading one minor version at a time.
    def steps(in_steps)
      from = @current_rails
      ruby = @app_ruby # the Ruby the app runs at each step, after the upgrades suggested so far
      max_now = @current_max_ruby
      @hops.map do |hop|
        note, upgraded = ruby_note(hop, ruby, max_now)
        step = { version: hop[:version], from: from, ruby: note, ruby_upgrade: upgraded,
                 checks: in_order(in_steps.select { |entry| step_for(entry) == hop[:version] }) }
        ruby = upgraded || ruby
        from = hop[:version]
        max_now = hop[:max_ruby]
        step
      end
    end

    # An API removed in one of the step versions is fixed as part of that step. A Ruby too old or too new for
    # the target is checked against the target, so it sits in the last step, next to its Ruby note.
    def step_for(entry)
      return @hops.last&.dig(:version) if entry[:section] == "Ruby Version" && entry[:kind] == :blocker

      removed = entry[:removed_in]&.to_s
      removed if removed && %i[blocker to_fix].include?(entry[:kind]) && @hops.any? { |hop| hop[:version] == removed }
    end

    # Removed by a Rails past the target: not needed now, but found in the same scan.
    def ahead?(entry)
      entry[:kind] == :to_fix && entry[:removed_in] && Gem::Version.correct?(@target_rails) &&
        Gem::Version.new(entry[:removed_in].to_s) > Gem::Version.new(@target_rails)
    end

    # [note, Ruby to upgrade to before this step or nil]. A Ruby too old for the step is upgraded on the Rails
    # before it, to the newest Ruby both support, so later steps need as few Ruby upgrades as possible.
    def ruby_note(hop, ruby, max_now)
      return ["Ruby requirements for Rails #{hop[:version]} are unknown", nil] unless hop[:min_ruby]

      range = "Ruby #{hop[:min_ruby]}–#{short(hop[:max_ruby])}"
      version = ruby && Gem::Version.new(ruby)
      if version.nil? then ["Needs #{range}", nil]
      elsif version < Gem::Version.new(hop[:min_ruby])
        upgraded = [max_now, hop[:max_ruby]].compact.min_by { |v| Gem::Version.new(v) }
        ["Needs #{range}: upgrade Ruby from #{short(ruby)} to #{short(upgraded)} first", short(upgraded)]
      elsif version > Gem::Version.new(hop[:max_ruby]) then ["Needs #{range}: Ruby #{short(ruby)} is newer than it supports", nil]
      else ["Needs #{range}: #{short(ruby)} works", nil]
      end
    end

    def short(ruby)
      ruby.delete_suffix(".99")
    end
  end
end
