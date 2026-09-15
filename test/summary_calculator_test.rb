require 'minitest/autorun'
require_relative '../lib/rails_preflight/summary_calculator'

class SummaryCalculatorTest < Minitest::Test
  def test_classifies_findings_by_kind
    results = [
      {
        title: "Ruby Version",
        status: :failed,
        checks: [
          { message: "BLOCKER: Ruby too old", status: :failed },
          { message: "EOL Ruby", status: :warning },
          { message: "Ruby unknown", status: :warning, kind: :unknown },
          { message: "Nice tip", status: :passed, kind: :tip },
          { message: "All good", status: :passed }
        ]
      }
    ]

    summary = RailsPreflight::SummaryCalculator.new(results, "7.2").calculate

    assert_equal ["BLOCKER: Ruby too old"], summary[:blockers].map { |f| f[:message] }
    assert_equal ["EOL Ruby"], summary[:to_fix].map { |f| f[:message] }
    assert_equal ["Ruby unknown"], summary[:unknowns].map { |f| f[:message] }
  end

  def test_findings_keep_their_section_and_occurrences
    results = [
      {
        title: "Deprecation Warnings",
        status: :warning,
        checks: [{ message: "Use update", status: :warning, grouped: true, stats: { occurrences: 12 } }]
      }
    ]

    summary = RailsPreflight::SummaryCalculator.new(results, "7.2").calculate

    assert_equal [{ section: "Deprecation Warnings", message: "Use update", occurrences: 12 }], summary[:to_fix]
  end

  def test_path_lists_blocking_sections_first_then_the_upgrade
    results = [
      { title: "Private Gems", status: :warning, checks: [{ message: "2 private gems", status: :warning, kind: :unknown }] },
      { title: "Docker Configuration", status: :passed, checks: [{ message: "Fine", status: :passed }] },
      {
        title: "Ruby Version",
        status: :failed,
        checks: [{ message: "Too old", status: :failed }, { message: "EOL", status: :warning }]
      },
      { title: "Configuration", status: :warning, checks: [{ message: "load_defaults behind", status: :warning }] }
    ]

    path = RailsPreflight::SummaryCalculator.new(results, "7.1", "6.1.7").calculate[:suggested_path]

    assert_equal [
      "Ruby Version: 1 blocker, 1 to fix",
      "Private Gems: 1 couldn't check",
      "Configuration: 1 to fix",
      "Upgrade Rails 6.1.7 → 7.1"
    ], path
  end

  def test_clean_results_only_suggest_the_upgrade
    results = [{ title: "Ruby Version", status: :passed, checks: [{ message: "Compatible", status: :passed }] }]

    summary = RailsPreflight::SummaryCalculator.new(results, "7.1").calculate

    assert_empty summary[:blockers]
    assert_empty summary[:to_fix]
    assert_empty summary[:unknowns]
    assert_equal ["Upgrade Rails to 7.1"], summary[:suggested_path]
  end
end
