module RailsPreflight
  class SummaryCalculator
    # Explicit check[:kind] (:unknown, :tip) wins; otherwise failures block and warnings need fixing.
    KIND_BY_STATUS = { failed: :blocker, warning: :to_fix }.freeze
    LABELS = { blocker: "blocker", to_fix: "to fix", unknown: "couldn't check" }.freeze

    def initialize(results, target_rails = "Unknown", current_rails = nil)
      @results = results
      @target_rails = target_rails
      @current_rails = current_rails
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
        section[:checks].select { |check| kind(check) == wanted }.map do |check|
          { section: section[:title], message: check[:message], occurrences: check.dig(:stats, :occurrences) }
        end
      end
    end

    # One step per section with work, sections with blockers first, then the upgrade itself.
    def suggested_path
      sections = @results.filter_map do |section|
        counts = section[:checks].map { |check| kind(check) }.tally.slice(:blocker, :to_fix, :unknown)
        [section[:title], counts] if counts.any?
      end
      blocking, rest = sections.partition { |_, counts| counts[:blocker] }

      steps = (blocking + rest).map do |title, counts|
        "#{title}: " + counts.map { |kind, n| "#{n} #{label(kind, n)}" }.join(", ")
      end
      steps << (@current_rails ? "Upgrade Rails #{@current_rails} → #{@target_rails}" : "Upgrade Rails to #{@target_rails}")
    end

    def label(kind, count)
      kind == :blocker && count > 1 ? "blockers" : LABELS[kind]
    end
  end
end
