require "minitest/autorun"
require_relative "../lib/rails_preflight/report_generator"
require_relative "../lib/rails_preflight/summary_calculator"

class ReportGeneratorTest < Minitest::Test
  HOPS = [{ version: "6.0", min_ruby: "2.5.0", max_ruby: "2.7.99" }].freeze

  def test_escapes_dynamic_content_in_report
    html = render([
      { title: "Deprecation Warnings", status: :failed, confidence: :medium, checks: [
        grouped_check("<b>unsafe blocker</b>", "https://guides.rubyonrails.org/6_0_release_notes.html", status: :failed, removed_in: "6.0",
                      details: [{ file: "app/models/user.rb", line: 12, snippet: "<script>alert(1)</script>" }]),
        { message: "<b>unsafe broken</b>", status: :failed, kind: :broken, removed_in: "5.1" }
      ] },
      { title: "Private Gems", status: :warning, confidence: :high, checks: [
        { message: "Private gems (1)", status: :warning, kind: :unknown, details: ["<img src=x>"] }
      ] }
    ], app: "<i>app</i>")

    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_includes html, "&lt;b&gt;unsafe blocker&lt;/b&gt;"
    assert_includes html, "&lt;b&gt;unsafe broken&lt;/b&gt;"
    assert_includes html, "&lt;img src=x&gt;"
    assert_includes html, "&lt;i&gt;app&lt;/i&gt;"
    refute_match(/<script>|<b>unsafe|<img|<i>app/, html)
  end

  def test_links_findings_to_their_release_notes_over_https_only
    html = render([{ title: "Deprecation Warnings", status: :warning, confidence: :medium, checks: [
      grouped_check("Use update", "https://guides.rubyonrails.org/6_1_release_notes.html#active-record-removals"),
      grouped_check("Sneaky", "javascript:alert(1)")
    ] }])

    assert_includes html, 'href="https://guides.rubyonrails.org/6_1_release_notes.html#active-record-removals" target="_blank" rel="noopener">6.1 notes ↗'
    refute_includes html, "javascript:alert(1)"
  end

  def test_quoted_names_are_code_but_apostrophes_are_not
    html = render([{ title: "Configuration", status: :warning, checks: [
      { message: "'update_attributes' doesn't exist; use 'update'.", status: :warning }
    ] }])

    assert_includes html, "<code>update_attributes</code> doesn&#39;t exist; use <code>update</code>."
  end

  def test_route_shows_each_step_then_later_versions_faded
    html = render([{ title: "Deprecation Warnings", status: :failed, confidence: :medium, checks: [
      grouped_check("Gone in 6.0", nil, status: :failed, removed_in: "6.0"),
      grouped_check("Gone in 6.1", nil, removed_in: "6.1")
    ] }], later_rails: %w[6.1 7.0])

    assert_includes html, "One step, and Ruby 2.5.9 can stay. 1 blocker."
    assert_includes html, '<a class="stop now" href="#steps-h"><span class="dot"></span><span class="v">5.2</span><span class="b">you are here</span></a>'
    assert_includes html, '<a class="stop has target" href="#s6-0"><span class="dot"></span><span class="v">6.0</span><span class="b">1 blocker</span></a>'
    assert_includes html, '<a class="stop ahead" href="#a6-1"><span class="dot"></span><span class="v">6.1</span><span class="b">1 seen ahead</span></a>'
    assert_includes html, '<a class="stop ahead" href="#ahead-h"><span class="dot"></span><span class="v">7.0</span><span class="b">none seen</span></a>'
    assert_includes html, "Nothing in the code is removed by 7.0."
  end

  private

  def render(results, app: "example", later_rails: [])
    summary = RailsPreflight::SummaryCalculator.new(results, "6.0", "5.2.8", hops: HOPS, app_ruby: "2.5.9").calculate
    RailsPreflight::ReportGenerator.new(app: app, current_rails: "5.2.8", target_rails: "6.0", ruby: ["2.5.9", ".ruby-version"],
                                        later_rails: later_rails, results: results, summary: summary).generate
  end

  def grouped_check(message, guide_link, status: :warning, removed_in: nil, details: [])
    {
      message: message, status: status, grouped: true, guide_link: guide_link, removed_in: removed_in, details: details,
      stats: { occurrences: 1, occurrences_app: 1, occurrences_test: 0, files: 1, models: 0, controllers: 0, severity: "warning", fix_effort: "low" }
    }
  end
end
