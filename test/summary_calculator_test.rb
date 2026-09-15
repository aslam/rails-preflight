require 'minitest/autorun'
require_relative '../lib/rails_preflight/summary_calculator'

class SummaryCalculatorTest < Minitest::Test
  def test_calculate_low_risk_small_effort
    results = [
      { title: "Ruby Version", status: :passed, checks: [{ status: :passed }] },
      { title: "Private Gems", status: :passed, checks: [] },
      { title: "Deprecation Warnings", status: :passed, checks: [] }
    ]

    calculator = RailsPreflight::SummaryCalculator.new(results)
    summary = calculator.calculate

    assert_equal "Low", summary[:overall_risk]
    assert_equal "Small", summary[:estimated_effort]
    assert_empty summary[:primary_blockers]
  end

  def test_calculate_high_risk_private_gems
    results = [
      { 
        title: "Private Gems", 
        status: :warning, 
        checks: [
          { message: "Private Gems Detected", status: :warning, details: ["gem_a", "gem_b", "gem_c", "gem_d", "gem_e", "gem_f"] }
        ] 
      }
    ]

    calculator = RailsPreflight::SummaryCalculator.new(results)
    summary = calculator.calculate

    assert_equal "Medium", summary[:overall_risk] # Only warnings, but many
    assert_equal "Large", summary[:estimated_effort] # > 5 private gems
    assert_includes summary[:primary_blockers], "6 private gems (unknown compatibility)"
  end

  def test_calculate_blocker_ruby
    results = [
      { 
        title: "Ruby Version", 
        status: :failed, 
        checks: [
          { message: "BLOCKER: Ruby too old", status: :failed }
        ] 
      }
    ]

    calculator = RailsPreflight::SummaryCalculator.new(results)
    summary = calculator.calculate

    assert_equal "High", summary[:overall_risk]
    assert_equal "Large", summary[:estimated_effort]
    assert_includes summary[:primary_blockers], "BLOCKER: Ruby too old"
  end
  def test_calculate_score
    results = [
      { 
        title: "Private Gems", 
        status: :warning, 
        checks: [
          { message: "Private Gems Detected", status: :warning, details: ["a", "b"] } # 2 * 3 = 6
        ] 
      },
      { 
        title: "Ruby Version", 
        status: :failed, 
        checks: [{ message: "BLOCKER", status: :failed }] # +5
      },
      {
        title: "Docker Configuration",
        status: :warning,
        checks: [] # +2
      },
      {
        title: "Deprecation Warnings",
        status: :warning,
        checks: [
            { status: :warning, message: "Deprecation A" },
            { status: :warning, message: "Deprecation B" },
            { status: :warning, message: "Deprecation C" },
            { status: :warning, message: "Deprecation D" },
            { status: :warning, message: "Deprecation E" } 
        ] # 5 * 0.2 = 1.0
      }
    ]
    # Total: 6 + 5 + 2 + 1.0 = 14.0

    calculator = RailsPreflight::SummaryCalculator.new(results)
    summary = calculator.calculate

    assert_equal "14.0 / 40", summary[:upgrade_score]
  end

  def test_recommendation_only_does_not_raise_risk
    results = [
      {
        title: "Deprecation Warnings",
        status: :warning,
        checks: [
          { status: :warning, message: "💡 Recommendation: Install `rubocop-rails` gem." }
        ]
      }
    ]

    calculator = RailsPreflight::SummaryCalculator.new(results)
    summary = calculator.calculate

    assert_equal "Low", summary[:overall_risk]
    assert_equal "0.0 / 40", summary[:upgrade_score]
  end

  def test_docker_configuration_contributes_to_summary
    results = [
      {
        title: "Docker Configuration",
        status: :warning,
        checks: [{ status: :warning, message: "Locale missing" }]
      }
    ]

    calculator = RailsPreflight::SummaryCalculator.new(results)
    summary = calculator.calculate

    assert_equal "2.0 / 40", summary[:upgrade_score]
    assert_includes summary[:suggested_path], "Address Dockerfile findings"
  end

  def test_score_is_capped_at_40
    results = [
      {
        title: "Private Gems",
        status: :warning,
        checks: [{ message: "Private Gems Detected", status: :warning, details: Array.new(20) { |i| "gem_#{i}" } }]
      }
    ]

    assert_equal "40.0 / 40", RailsPreflight::SummaryCalculator.new(results).calculate[:upgrade_score]
  end

  def test_calculate_deprecation_occurrences
    results = [
      {
        title: "Deprecation Warnings",
        status: :warning,
        checks: [
          { status: :warning, message: "Deprecation A", stats: { occurrences: 10 } },
          { status: :warning, message: "Deprecation B", stats: { occurrences: 5 } },
          { status: :warning, message: "Deprecation C" } # Default to 1
        ]
      }
    ]

    calculator = RailsPreflight::SummaryCalculator.new(results)
    summary = calculator.calculate

    # 3 distinct types, 10 + 5 + 1 = 16 total occurrences
    assert_includes summary[:primary_blockers], "3 distinct deprecation types (16 total occurrences)"
  end

  def test_generate_suggested_path
    results = [
      {
        title: "Ruby Version",
        status: :failed,
        checks: [{ message: "BLOCKER: Need Ruby 3.1", status: :failed }]
      },
      {
        title: "Private Gems",
        status: :warning,
        checks: [{ message: "Private Gems Detected", status: :warning, details: ["private_gem"] }]
      },
      {
         title: "Deprecation Warnings",
         status: :warning,
         checks: [{ status: :warning, message: "Deprecation A", stats: { occurrences: 1 } }]
      }
    ]

    calculator = RailsPreflight::SummaryCalculator.new(results, "7.1", "6.1.7")
    summary = calculator.calculate
    path = summary[:suggested_path]

    assert_includes path, "Upgrade Ruby (Blocker detected: BLOCKER: Need Ruby 3.1)"
    assert_includes path, "Audit 1 Private Gems for Rails 7.1 readiness"
    assert_includes path, "Fix 1 distinct deprecation patterns (e.g. update_attributes, etc.)"
    assert_includes path, "Upgrade Rails 6.1.7 → 7.1"
  end
end
