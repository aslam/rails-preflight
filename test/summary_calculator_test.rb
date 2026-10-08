require 'minitest/autorun'
require_relative '../lib/rails_preflight/summary_calculator'

class SummaryCalculatorTest < Minitest::Test
  def test_classifies_findings_by_kind
    results = [
      {
        title: "Ruby Version",
        status: :failed,
        checks: [
          { message: "Ruby too old", status: :failed },
          { message: "EOL Ruby", status: :warning },
          { message: "Ruby unknown", status: :warning, kind: :unknown },
          { message: "Nice tip", status: :passed, kind: :tip },
          { message: "All good", status: :passed }
        ]
      }
    ]

    summary = RailsPreflight::SummaryCalculator.new(results, "7.2").calculate

    assert_equal ["Ruby too old"], summary[:blockers].map { |f| f[:message] }
    assert_equal ["EOL Ruby"], summary[:to_fix].map { |f| f[:message] }
    assert_equal ["Ruby unknown"], summary[:unknowns].map { |f| f[:message] }
  end

  def test_already_broken_findings_come_first_and_stay_out_of_the_steps
    results = [
      { title: "Configuration", status: :warning, checks: [{ message: "Old defaults", status: :warning }] },
      { title: "Deprecation Warnings", status: :failed, checks: [{ message: "render :text", status: :failed, kind: :broken, removed_in: "5.1" }] }
    ]
    hops = [{ version: "6.0", min_ruby: "2.5.0", max_ruby: "2.7.99" }]

    summary = RailsPreflight::SummaryCalculator.new(results, "6.0", "5.2.8", hops: hops).calculate

    assert_equal ["render :text"], summary[:broken].map { |f| f[:message] }
    assert_empty summary[:blockers]
    assert_equal [["Deprecation Warnings", "render :text", :broken], ["Configuration", "Old defaults", :to_fix]],
                 summary[:before].map { |e| e.values_at(:section, :message, :kind) }
    assert_empty summary[:steps].first[:checks]
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

  def test_path_prepares_then_steps_through_each_minor_version
    results = [
      { title: "Ruby Version", status: :failed, checks: [{ message: "Too old", status: :failed }] },
      { title: "Private Gems", status: :warning, checks: [{ message: "1 private gem", status: :warning, kind: :unknown }] },
      { title: "Docker Configuration", status: :passed, checks: [{ message: "Fine", status: :passed }] },
      {
        title: "Deprecation Warnings",
        status: :failed,
        checks: [
          { message: "Old API", status: :failed, removed_in: "7.1", stats: { occurrences: 4 } },
          { message: "Older API", status: :warning, removed_in: "6.1" },
          { message: "Later API", status: :warning, removed_in: "7.2" },
          { message: "Use rubocop", status: :passed, kind: :tip }
        ]
      }
    ]
    hops = [
      { version: "7.0", min_ruby: "2.7.0", max_ruby: "3.2.99" },
      { version: "7.1", min_ruby: "2.7.0", max_ruby: "3.4.99" }
    ]

    summary = RailsPreflight::SummaryCalculator.new(results, "7.1", "6.1.7", hops: hops, app_ruby: "2.7.8").calculate

    assert_equal ["Older API", "Use rubocop"], summary[:before].map { |e| e[:message] }
    assert_equal [["7.0", "6.1.7", "Needs Ruby 2.7.0–3.2: 2.7.8 works", []], ["7.1", "7.0", "Needs Ruby 2.7.0–3.4: 2.7.8 works", ["Too old", "Old API"]]],
                 summary[:steps].map { |step| [step[:version], step[:from], step[:ruby], step[:checks].map { |e| e[:message] }] }
    assert_equal({ "7.2" => ["Later API"] }, summary[:ahead].transform_values { |entries| entries.map { |e| e[:message] } })
    assert_equal ["1 private gem"], summary[:cant_see].map { |e| e[:message] }
  end

  def test_ruby_note_says_when_to_upgrade_ruby
    hops = [{ version: "7.2", min_ruby: "3.1.0", max_ruby: "3.4.99" }]

    steps = RailsPreflight::SummaryCalculator.new([], "7.2", "7.1.3", hops: hops, app_ruby: "2.7.8").calculate[:steps]

    assert_equal [["Needs Ruby 3.1.0–3.4: upgrade Ruby from 2.7.8 to 3.4 first", "3.4"]], steps.map { |step| step.values_at(:ruby, :ruby_upgrade) }
  end

  def test_ruby_is_upgraded_as_far_as_the_rails_before_the_step_allows
    hops = [
      { version: "6.0", min_ruby: "2.5.0", max_ruby: "2.7.99" },
      { version: "6.1", min_ruby: "2.5.0", max_ruby: "3.0.99" },
      { version: "7.0", min_ruby: "2.7.0", max_ruby: "3.2.99" },
      { version: "7.1", min_ruby: "2.7.0", max_ruby: "3.4.99" },
      { version: "7.2", min_ruby: "3.1.0", max_ruby: "3.4.99" }
    ]

    steps = RailsPreflight::SummaryCalculator.new([], "7.2", "5.2.8", hops: hops, app_ruby: "2.5.9", current_max_ruby: "2.6.99").calculate[:steps]

    assert_equal [
      "Needs Ruby 2.5.0–2.7: 2.5.9 works",
      "Needs Ruby 2.5.0–3.0: 2.5.9 works",
      "Needs Ruby 2.7.0–3.2: upgrade Ruby from 2.5.9 to 3.0 first",
      "Needs Ruby 2.7.0–3.4: 3.0 works",
      "Needs Ruby 3.1.0–3.4: upgrade Ruby from 3.0 to 3.4 first"
    ], steps.map { |step| step[:ruby] }
  end

  def test_clean_results_without_version_data_suggest_just_the_target
    results = [{ title: "Configuration", status: :passed, checks: [{ message: "Fine", status: :passed }] }]

    summary = RailsPreflight::SummaryCalculator.new(results, "7.1").calculate

    assert_empty summary[:blockers]
    assert_empty summary[:to_fix]
    assert_empty summary[:unknowns]
    assert_equal [{ version: "7.1", from: nil, ruby: "Ruby requirements for Rails 7.1 are unknown", ruby_upgrade: nil, checks: [] }], summary[:steps]
  end
end
