require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rails_preflight/database_analyzer"

class DatabaseAnalyzerTest < Minitest::Test
  def test_structure_sql_is_named_as_what_the_report_cant_see
    Dir.mktmpdir do |app|
      check = -> { RailsPreflight::DatabaseAnalyzer.new(app).run[:checks].first }
      assert_equal "No db/schema.rb found. Skipping database checks.", check.call[:message]

      FileUtils.mkdir_p(File.join(app, "db"))
      File.write(File.join(app, "db", "structure.sql"), "CREATE TABLE users (id integer);\n")
      assert_equal :unknown, check.call[:kind]
      assert_includes check.call[:message], "db/structure.sql, which isn't read yet"
    end
  end
end
