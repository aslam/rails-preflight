require "minitest/autorun"
require "yaml"
require_relative "../lib/rails_preflight/deprecation_analyzer"

class DeprecationAnalyzerTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    # Create fake deprecations.yml
    @db_dir = File.join(@tmp_dir, "database")
    FileUtils.mkdir_p(@db_dir)
    
    yaml_content = {
      "deprecations" => [
        {
          "id" => "test_rule",
          "pattern" => "deprecated_method",
          "message" => "Don't use this",
          "confidence" => "High",
          "guide_link" => "http://example.com",
          "recategorization" => "Rails 6.0 -> 6.1",
          "removed_in" => "7.0"
        }
      ]
    }.to_yaml
    
    File.write(File.join(@db_dir, "deprecations.yml"), yaml_content)
    
    # Create fake app code
    @app_dir = File.join(@tmp_dir, "app")
    FileUtils.mkdir_p(@app_dir)
  end

  def teardown
    FileUtils.remove_entry @tmp_dir
  end

  def test_detects_and_structures_deprecation
    File.write(File.join(@app_dir, "model.rb"), "def foo\n  deprecated_method\nend")
    File.write(File.join(@app_dir, "user.rb"), "User.update_attributes(name: 'foo')")

    analyzer = RailsPreflight::DeprecationAnalyzer.new(@tmp_dir, File.join(@db_dir, "deprecations.yml"))
    result = analyzer.run

    assert_equal :warning, result[:status]
    check = result[:checks].first

    assert_match(/High Confidence/, check[:message])
    assert_match /Guide.*example\.com/, check[:message]

    detail = check[:details]
    assert_equal "High", detail[:confidence]
    assert_equal "Rails 6.0 -> 6.1", detail[:recategorization]
    assert_equal "app/model.rb", detail[:file]
    assert_equal 2, detail[:line]
  end
end
