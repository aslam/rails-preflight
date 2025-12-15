require 'minitest/autorun'
require_relative '../lib/rails_upgrade_audit/summary_calculator'

class SummaryCalculatorTest < Minitest::Test
  def test_calculate_low_risk_small_effort
    results = [
      { title: "Ruby Version", status: :passed, checks: [{ status: :passed }] },
      { title: "Private Gems", status: :passed, checks: [] },
      { title: "Deprecation Warnings", status: :passed, checks: [] }
    ]

    calculator = RailsUpgradeAudit::SummaryCalculator.new(results)
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

    calculator = RailsUpgradeAudit::SummaryCalculator.new(results)
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

    calculator = RailsUpgradeAudit::SummaryCalculator.new(results)
    summary = calculator.calculate

    assert_equal "High", summary[:overall_risk]
    assert_equal "Large", summary[:estimated_effort]
    assert_includes summary[:primary_blockers], "BLOCKER: Ruby too old"
  end
end
