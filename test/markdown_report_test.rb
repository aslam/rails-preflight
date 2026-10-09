require "minitest/autorun"
require_relative "../lib/rails_preflight/version"
require_relative "../lib/rails_preflight/report_generator"
require_relative "../lib/rails_preflight/markdown_report"
require_relative "../lib/rails_preflight/summary_calculator"

class MarkdownReportTest < Minitest::Test
  HOPS = [{ version: "6.0", min_ruby: "2.5.0", max_ruby: "2.7.99" }].freeze

  def test_steps_list_each_finding_with_its_files_and_source
    md = render([
      { title: "Deprecation Warnings", status: :failed, checks: [
        { message: "'update_attributes' was removed. Use 'update'.", status: :failed, removed_in: "6.0", source: "https://guides.rubyonrails.org/6_0_release_notes.html",
          files: [{ file: "app/models/user.rb", line: 12, snippet: "user.update_attributes(x)", test: false }] },
        { message: "Gone later", status: :warning, removed_in: "6.1", files: [{ file: "lib/a.rb", line: 1, snippet: "a" }] }
      ] },
      { title: "Private Gems", status: :warning, checks: [{ message: "Private gems (1)", status: :warning, kind: :unknown, names: ["acme"] }] }
    ])

    assert_includes md, "# example: Rails 5.2.8 to 6.0\n\nOne step, and Ruby 2.5.9 can stay. 1 blocker.\n"
    assert_includes md, "## Step 1: 5.2.8 to 6.0\n\nNeeds Ruby 2.5.0–2.7: 2.5.9 works.\n\n" \
                        "- [ ] **Blocker:** `update_attributes` was removed. Use `update`. ([source](https://guides.rubyonrails.org/6_0_release_notes.html))\n" \
                        "  - `app/models/user.rb:12` `user.update_attributes(x)`\n"
    assert_includes md, "## Ahead: removed in 6.1, not needed for 6.0\n\n- [ ] **To fix:** Gone later\n  - `lib/a.rb:1` `a`\n"
    assert_includes md, "## Couldn't check\n\n- Private gems (1): acme\n"
  end

  def test_snippets_with_backticks_stay_code_and_only_https_sources_link
    md = render([{ title: "Deprecation Warnings", status: :failed, checks: [
      { message: "Shell out", status: :failed, removed_in: "6.0", source: "javascript:alert(1)",
        files: [{ file: "lib/x.rb", line: 3, snippet: "`rake stats`" }] }
    ] }])

    assert_includes md, "  - `lib/x.rb:3` `` `rake stats` ``\n"
    refute_includes md, "javascript:"
  end

  private

  def render(results)
    summary = RailsPreflight::SummaryCalculator.new(results, "6.0", "5.2.8", hops: HOPS, app_ruby: "2.5.9").calculate
    RailsPreflight::MarkdownReport.new(app: "example", current_rails: "5.2.8", target_rails: "6.0", results: results, summary: summary).generate
  end
end
