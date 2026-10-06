require "minitest/autorun"
require_relative "../lib/rails_preflight/report_generator"

class ReportGeneratorTest < Minitest::Test
  def test_escapes_dynamic_content_in_report
    data = {
      target_rails: "6.1",
      summary: {
        broken: [{ section: "Deprecation Warnings", message: "<b>unsafe broken</b>" }],
        blockers: [{ section: "Deprecation Warnings", message: "<b>unsafe blocker</b>", occurrences: 1 }],
        to_fix: [],
        unknowns: [],
        suggested_path: [{ title: "Review <script>alert(1)</script>", items: [{ section: "Deprecation Warnings", message: "<b>unsafe step</b>" }] }]
      },
      results: [
        {
          title: "Deprecation Warnings",
          status: :warning,
          confidence: :high,
          checks: [
            {
              message: "Potential XSS",
              status: :warning,
              grouped: true,
              stats: {
                occurrences: 1,
                occurrences_app: 1,
                occurrences_test: 0,
                files: 1,
                models: 0,
                controllers: 0,
                severity: "warning",
                fix_effort: "low"
              },
              details: [
                {
                  file: "app/models/user.rb",
                  line: 12,
                  snippet: "<script>alert(1)</script>"
                }
              ]
            }
          ]
        }
      ]
    }

    html = RailsPreflight::ReportGenerator.new(data).generate

    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_includes html, "&lt;b&gt;unsafe blocker&lt;/b&gt;"
    assert_includes html, "&lt;b&gt;unsafe broken&lt;/b&gt;"
    assert_includes html, "Already broken"
    refute_includes html, "<script>alert(1)</script>"
    refute_includes html, "<b>unsafe step</b>"
    # Summary findings link to their section
    assert_includes html, 'href="#section-deprecation-warnings"'
    assert_includes html, 'id="section-deprecation-warnings"'
  end

  def test_links_deprecations_to_their_upgrade_guide
    html = RailsPreflight::ReportGenerator.new(
      target_rails: "7.2",
      results: [{
        title: "Deprecation Warnings", status: :warning, confidence: :medium,
        checks: [
          grouped_check("Use update", "https://guides.rubyonrails.org/6_1_release_notes.html"),
          grouped_check("Sneaky", "javascript:alert(1)")
        ]
      }]
    ).generate

    assert_includes html, 'href="https://guides.rubyonrails.org/6_1_release_notes.html"'
    refute_includes html, "javascript:alert(1)"
  end

  private

  def grouped_check(message, guide_link)
    {
      message: message, status: :warning, grouped: true, guide_link: guide_link, details: [],
      stats: { occurrences: 1, occurrences_app: 1, occurrences_test: 0, files: 1, models: 0, controllers: 0, severity: "warning", fix_effort: "low" }
    }
  end
end
