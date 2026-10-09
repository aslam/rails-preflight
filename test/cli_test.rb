require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"
require "fileutils"

class CliTest < Minitest::Test
  BIN = File.expand_path("../bin/rails-preflight", __dir__)
  APP = File.expand_path("../fixtures/valid_app", __dir__) # Ruby 2.5.9: Rails 8.1 is blocked, nothing is broken

  def test_stdout_prints_json_and_fail_on_sets_the_exit_code
    out, err, status = rails_preflight("--format", "json", "--stdout", "--fail-on", "blockers")

    assert out.start_with?("{"), "no JSON on stdout; stderr: #{err}"
    report = JSON.parse(out)
    assert_equal 1, report["schema"]
    assert_equal({ "broken" => 0, "blockers" => 1 }, report["counts"].slice("broken", "blockers"))
    blocker = report["steps"].last["findings"].find { |finding| finding["kind"] == "blocker" }
    assert_equal %w[section kind message], blocker.keys.first(3)
    refute blocker.key?("status")
    assert_includes err, "Starting Audit"
    assert_equal 1, status.exitstatus
    refute File.exist?(File.join(APP, "rails_preflight_report.html"))

    assert_equal 0, rails_preflight("--format", "json", "--stdout", "--fail-on", "broken")[2].exitstatus
    assert_equal 0, rails_preflight("--format", "json", "--stdout")[2].exitstatus
  end

  def test_each_format_is_written_into_the_app
    Dir.mktmpdir do |dir|
      app = File.join(dir, "app")
      FileUtils.cp_r(APP, app)
      { "markdown" => "rails_preflight_report.md", "json" => "rails_preflight_report.json" }.each do |format, file|
        out, = rails_preflight("--format", format, app: app)

        assert_includes out, "Report generated at: #{File.join(app, file)}"
        refute_includes out, "browser"
      end
      assert File.read(File.join(app, "rails_preflight_report.md")).start_with?("# app: Rails")
      assert_equal 1, JSON.parse(File.read(File.join(app, "rails_preflight_report.json")))["schema"]
      refute File.exist?(File.join(app, "rails_preflight_report.html"))
    end
  end

  def test_rejects_unknown_options_values
    assert_includes rails_preflight("--format", "pdf")[1], "--format must be html, markdown or json"
    assert_includes rails_preflight("--fail-on", "warnings")[1], "--fail-on must be blockers or broken"
  end

  private

  def rails_preflight(*args, app: APP)
    Open3.capture3(RbConfig.ruby, BIN, "--offline", *args, "8.1", app)
  end
end
