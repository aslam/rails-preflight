require 'json'

module RailsPreflight
  # The report as JSON, for CI and other tools. Findings are the analyzers' checks with their parts (see
  # SummaryCalculator), plus :section and :kind. No timestamp: the same app gives the same output.
  # Schema 1 may still change before 1.0; the number goes up when it does.
  class JsonReport
    SCHEMA = 1

    def initialize(data)
      @data = data
      @summary = data[:summary] || {}
    end

    def generate
      ruby, source = @data[:ruby]
      report = {
        schema: SCHEMA,
        tool: { name: "rails-preflight", version: VERSION },
        app: @data[:app],
        current_rails: @data[:current_rails],
        target_rails: @data[:target_rails],
        ruby: ({ version: ruby, source: source } if ruby),
        offline: @data[:offline],
        verdict: @summary[:verdict],
        counts: %i[broken blockers to_fix unknowns].to_h { |key| [key, @summary.fetch(key, []).size] },
        before: @summary.fetch(:before, []).map { |entry| finding(entry) },
        steps: @summary.fetch(:steps, []).map do |step|
          step.slice(:from, :version, :ruby, :ruby_upgrade).merge(findings: step[:checks].map { |entry| finding(entry) })
        end,
        ahead: @summary.fetch(:ahead, {}).transform_values { |entries| entries.map { |entry| finding(entry) } },
        cant_see: @summary.fetch(:cant_see, []).map { |entry| finding(entry) }
      }
      "#{JSON.pretty_generate(report)}\n"
    end

    private

    # :status is how the analyzer saw it; :kind is what the report counts it as.
    def finding(entry)
      entry.slice(:section, :kind).merge(entry.except(:status, :section, :kind)).compact
    end
  end
end
