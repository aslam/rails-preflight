module RailsPreflight
  # The report as Markdown: for issues, PRs and coding agents. Takes the same data as ReportGenerator
  # and renders only the findings' parts, never the HTML.
  class MarkdownReport
    LABELS = { broken: "Broken", blocker: "Blocker", to_fix: "To fix", tip: "Tip" }.freeze

    def initialize(data)
      @data = data
      @summary = data[:summary] || {}
    end

    def generate
      out = []
      out << "# #{@data[:app]}: Rails #{@data[:current_rails] || 'unknown'} to #{@data[:target_rails]}"
      out << @summary[:verdict]
      counts = { "Already broken" => :broken, "Blockers" => :blockers, "To fix" => :to_fix, "Couldn't check" => :unknowns }
      out << counts.map { |label, key| "#{label}: #{@summary.fetch(key, []).size}" }.join(" · ")
      out << "> For a coding agent: take one step at a time, in order. After each step, run the test suite and fix what fails " \
             "before starting the next. Leave \"Ahead\" and \"Couldn't check\" alone unless asked."

      before = @summary.fetch(:before, [])
      out << section("Before you start#{" (on Rails #{@data[:current_rails]})" if @data[:current_rails]}", before) if before.any?
      @summary.fetch(:steps, []).each.with_index(1) do |step, i|
        title = "Step #{i}: #{step[:from] ? "#{step[:from]} to #{step[:version]}" : "Rails #{step[:version]}"}"
        out << section(title, step[:checks], "#{step[:ruby]}.")
      end
      @summary.fetch(:ahead, {}).each do |version, entries|
        out << section("Ahead: removed in #{version}, not needed for #{@data[:target_rails]}", entries)
      end
      cant_see = @summary.fetch(:cant_see, [])
      if cant_see.any?
        out << "## Couldn't check\n\n" + cant_see.map { |entry| "- #{text(entry[:message])}#{": #{entry[:names].join(', ')}" if entry[:names]&.any?}" }.join("\n")
      end
      out << "Made with [rails-preflight](#{ReportGenerator::REPO_URL}) #{VERSION}. Run it again after each step."
      "#{out.join("\n\n")}\n"
    end

    private

    def section(title, entries, note = nil)
      lines = entries.map { |entry| finding(entry) }
      lines = ["Nothing found."] if lines.empty?
      ["## #{title}", note, lines.join("\n")].compact.join("\n\n")
    end

    # A checkbox per finding to fix, then where it is: file:line with the matched line, or the files that use a gem.
    def finding(entry)
      label = LABELS.fetch(entry[:kind], entry[:kind].to_s)
      box = entry[:kind] == :tip ? "-" : "- [ ]"
      cite = " ([source](#{entry[:source]}))" if entry[:source].to_s.start_with?("https://")
      lines = ["#{box} **#{label}:** #{text(entry[:message])}#{cite}"]
      Array(entry[:files]).each do |hit|
        place = hit[:line] ? "#{hit[:file]}:#{hit[:line]}" : hit[:file]
        lines << "  - #{code(place)}#{" #{code(hit[:snippet])}" if hit[:snippet]}"
      end
      lines.join("\n")
    end

    # 'quoted' names become code, as in the HTML; an apostrophe inside a word (doesn't) stays.
    def text(message)
      message.to_s.gsub(/(?<!\w)'(.+?)'(?!\w)/) { code($1) }
    end

    # A code span that survives backticks in the snippet.
    def code(value)
      value = value.to_s
      fence = "`" * ((value.scan(/`+/).map(&:size).max || 0) + 1)
      pad = value.start_with?("`") || value.end_with?("`") ? " " : ""
      "#{fence}#{pad}#{value}#{pad}#{fence}"
    end
  end
end
