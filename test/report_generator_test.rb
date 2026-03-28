require "minitest/autorun"
require_relative "../lib/rails_preflight/report_generator"

class ReportGeneratorTest < Minitest::Test
  def test_escapes_dynamic_content_in_report
    data = {
      target_rails: "6.1",
      summary: {
        overall_risk: "Low",
        estimated_effort: "Small",
        primary_blockers: ["<b>unsafe blocker</b>"],
        upgrade_score: "0.0 / 40",
        suggested_path: ["Review <script>alert(1)</script>"]
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
    refute_includes html, "<script>alert(1)</script>"
  end
end
