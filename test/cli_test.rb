require "minitest/autorun"
require "json"
require "open3"

class CliTest < Minitest::Test
  BIN = File.expand_path("../bin/rails-preflight", __dir__)
  APP = File.expand_path("../fixtures/valid_app", __dir__) # Ruby 2.5.9: Rails 8.1 is blocked, nothing is broken

  def test_json_goes_to_stdout_and_fail_on_sets_the_exit_code
    out, err, status = rails_preflight("--format", "json", "--fail-on", "blockers")

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

    assert_equal 0, rails_preflight("--format", "json", "--fail-on", "broken")[2].exitstatus
    assert_equal 0, rails_preflight("--format", "json")[2].exitstatus
  end

  def test_rejects_unknown_options_values
    assert_includes rails_preflight("--format", "pdf")[1], "--format must be html, markdown or json"
    assert_includes rails_preflight("--fail-on", "warnings")[1], "--fail-on must be blockers or broken"
  end

  private

  def rails_preflight(*args)
    Open3.capture3(RbConfig.ruby, BIN, "--offline", *args, "8.1", APP)
  end
end
