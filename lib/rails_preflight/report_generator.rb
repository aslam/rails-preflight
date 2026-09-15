# lib/rails_preflight/report_generator.rb
require 'erb'

module RailsPreflight
  class ReportGenerator
    include ERB::Util

    SUMMARY_TILES = [
      [:blockers, "Blockers", "Must be fixed before the upgrade can work"],
      [:to_fix, "To fix", "Will warn or break along the way"],
      [:unknowns, "Couldn't check", "Not verified; review by hand"]
    ].freeze

    def initialize(data)
      @data = data
      @generated_at = Time.now
    end

    def generate
      # Quoted heredoc: #{} inside the template is evaluated by ERB at render time, not here.
      template = <<~'ERB'
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>RailsPreFlight Report</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 20px; }
            h1 { border-bottom: 2px solid #eee; padding-bottom: 10px; }
            .section { margin-bottom: 30px; border: 1px solid #ddd; border-radius: 8px; overflow: hidden; }
            .section-header { background: #f9f9f9; padding: 10px 15px; font-weight: bold; border-bottom: 1px solid #ddd; display: flex; justify-content: space-between; }
            .section-body { padding: 15px; }
            .item { margin-bottom: 10px; padding: 10px; border-radius: 4px; }
            .passed { background-color: #e6fffa; border-left: 5px solid #38b2ac; }
            .warning { background-color: #fffaf0; border-left: 5px solid #ed8936; }
            .failed { background-color: #fff5f5; border-left: 5px solid #f56565; }
            .badge { padding: 2px 8px; border-radius: 12px; font-size: 0.8em; color: white; }
            .badge-passed { background-color: #38b2ac; }
            .badge-warning { background-color: #ed8936; }
            .badge-failed { background-color: #f56565; }
            .badge-confidence-high { background-color: #2b6cb0; }
            .badge-confidence-medium { background-color: #dd6b20; }
            .badge-confidence-low { background-color: #718096; }
            .meta { color: #666; font-size: 0.9em; margin-bottom: 20px; }
            .summary-card { background: #f0f4f8; border: 1px solid #d9e2ec; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
            .summary-title { font-size: 1.2em; font-weight: bold; margin-bottom: 15px; color: #102a43; border-bottom: 1px solid #bcccdc; padding-bottom: 10px; }
            .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
            .summary-item { background: white; padding: 15px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
            .summary-label { font-size: 0.8em; color: #486581; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 5px; }
            .summary-value { font-size: 1.4em; font-weight: bold; }
            .count-blockers { color: #e53e3e; }
            .count-to_fix { color: #dd6b20; }
            .count-unknowns { color: #718096; }
            .summary-caption { font-size: 0.8em; color: #627d98; }
            .summary-list { margin-top: 15px; }
            .summary-list summary { cursor: pointer; font-weight: bold; color: #102a43; }
            .summary-list ul { margin: 5px 0 0; padding-left: 20px; font-size: 0.9em; }
            .unknown { background-color: #f7fafc; border-left: 5px solid #a0aec0; }
            .tip { background-color: #ebf8ff; border-left: 5px solid #63b3ed; }
            .footer { margin-top: 50px; padding-top: 20px; border-top: 1px solid #eee; text-align: center; color: #666; font-size: 0.9em; }
            .legend { display: inline-flex; flex-wrap: wrap; gap: 20px; align-items: center; justify-content: center; margin-top: 10px; }
            .legend-item { display: flex; align-items: center; gap: 8px; }
          </style>
        </head>
        <body>
          <h1>RailsPreFlight</h1>
          <div class="meta">
            Generated at: <%= h(@generated_at) %>
          </div>

          <% if @data[:summary] %>
            <div class="summary-card">
              <div class="summary-title">Rails <%= h(rails_jump) %></div>
              <div class="summary-grid">
                <% SUMMARY_TILES.each do |key, label, caption| %>
                  <div class="summary-item">
                    <div class="summary-label"><%= h(label) %></div>
                    <div class="summary-value <%= "count-#{key}" if @data[:summary][key].any? %>"><%= @data[:summary][key].size %></div>
                    <div class="summary-caption"><%= h(caption) %></div>
                  </div>
                <% end %>
              </div>
              <% SUMMARY_TILES.each do |key, label, _caption| %>
                <% next if @data[:summary][key].empty? %>
                <details class="summary-list"<%= " open" unless key == :to_fix %>>
                  <summary><%= h(label) %> (<%= @data[:summary][key].size %>)</summary>
                  <ul>
                    <% @data[:summary][key].each do |finding| %>
                      <li><a href="#<%= section_id(finding[:section]) %>"><%= h(finding[:section]) %></a>: <%= h(finding[:message]) %><%= occurrences_note(finding[:occurrences]) %></li>
                    <% end %>
                  </ul>
                </details>
              <% end %>
            </div>

            <% if @data[:summary][:suggested_path] && @data[:summary][:suggested_path].any? %>
              <div class="summary-card" style="border-left: 5px solid #38b2ac;">
                <div class="summary-title" style="color: #234e52; border-bottom-color: #38b2ac;">🚀 Suggested Upgrade Path</div>
                <div style="background: #fff; padding: 15px; border-radius: 4px;">
                  <ol style="margin: 0; padding-left: 20px; font-size: 1.1em;">
                    <% @data[:summary][:suggested_path].each do |step| %>
                      <li style="margin-bottom: 10px; padding-bottom: 10px; border-bottom: 1px dashed #eee;"><%= h(step) %></li>
                    <% end %>
                  </ol>
                </div>
              </div>
            <% end %>
          <% end %>

          <% @data[:results].each do |section| %>
            <div class="section" id="<%= section_id(section[:title]) %>">
              <div class="section-header">
                <div>
                  <span><%= h(section[:title]) %></span>
                  <% if section[:confidence] %>
                    <span class="badge <%= confidence_class(section[:confidence]) %>" style="margin-left: 10px; font-weight: normal; font-size: 0.7em; opacity: 0.9;" title="Confidence Level">
                      CONFIDENCE: <%= h(section[:confidence].to_s.upcase) %>
                    </span>
                  <% end %>
                </div>
                <span class="badge <%= status_class(section[:status]) %>"><%= h(section[:status].to_s.upcase) %></span>
              </div>
              <div class="section-body">
                <% if section[:checks].empty? %>
                  <div class="item passed">No issues found.</div>
                <% else %>
                  <% section[:checks].each do |check| %>
                    <div class="item <%= check[:kind] || check[:status] %>">
                      <% if check[:grouped] %>
                        <!-- Grouped Finding Header -->
                        <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 5px;">
                          <div>
                            <strong><%= h(check[:message]) %></strong>
                            <% if check[:stats][:fix_effort] %>
                              <span class="badge" style="background-color: #4a5568;">Fix: <%= h(check[:stats][:fix_effort].to_s.upcase) %></span>
                            <% end %>
                          </div>
                          <span class="badge" style="background-color: #718096;"><%= h(check[:stats][:severity]) %></span>
                        </div>
                        
                        <!-- Stats Row -->
                        <div style="display: flex; gap: 15px; font-size: 0.85em; color: #555; margin-bottom: 10px; border-bottom: 1px solid #e2e8f0; padding-bottom: 5px;">
                          <span>Occurrences: <strong><%= h(check[:stats][:occurrences]) %></strong> <span style="font-weight:normal; color:#718096; font-size:0.9em;">(App: <strong><%= h(check[:stats][:occurrences_app]) %></strong> / Test: <%= h(check[:stats][:occurrences_test]) %>)</span></span>
                          <span>Files: <strong><%= h(check[:stats][:files]) %></strong></span>
                          <span>Models: <strong><%= h(check[:stats][:models]) %></strong></span>
                          <span>Controllers: <strong><%= h(check[:stats][:controllers]) %></strong></span>
                        </div>

                        <!-- Expandable Details -->
                        <details>
                          <summary style="cursor: pointer; color: #3182ce; font-weight: 500; font-size: 0.9em; margin-bottom: 10px;">
                            Expand to see <%= h(check[:stats][:occurrences]) %> individual instances
                          </summary>
                          
                          <div style="background: white; border: 1px solid #e2e8f0; border-radius: 4px; max-height: 300px; overflow-y: auto;">
                            <table style="width: 100%; font-size: 0.85em; border-collapse: collapse;">
                              <thead style="background: #f7fafc; position: sticky; top: 0;">
                                <tr>
                                  <th style="text-align: left; padding: 8px; border-bottom: 1px solid #e2e8f0;">File</th>
                                  <th style="text-align: left; padding: 8px; border-bottom: 1px solid #e2e8f0;">Line</th>
                                  <th style="text-align: left; padding: 8px; border-bottom: 1px solid #e2e8f0;">Snippet</th>
                                </tr>
                              </thead>
                              <tbody>
                                <% check[:details].each do |occ| %>
                                  <tr style="border-bottom: 1px solid #edf2f7;">
                                    <td style="padding: 8px; color: #4a5568;"><%= h(occ[:file]) %></td>
                                    <td style="padding: 8px; color: #4a5568;"><%= h(occ[:line]) %></td>
                                    <td style="padding: 8px; font-family: monospace; color: #c53030;"><%= h(occ[:snippet]) %></td>
                                  </tr>
                                <% end %>
                              </tbody>
                            </table>
                          </div>
                        </details>

                      <% else %>
                        <!-- Standard Check -->
                        <div style="display: flex; justify-content: space-between;">
                          <strong><%= h(check[:message]) %></strong>
                          <% if check[:fix_effort] %>
                             <span class="badge" style="background-color: #cbd5e0; color: #2d3748; margin-left: 10px;">Fix: <%= h(check[:fix_effort].to_s.upcase) %></span>
                          <% end %>
                        </div>
                        <% if check[:details].is_a?(Array) %>
                          <ul>
                            <% check[:details].each do |detail| %>
                              <li><%= h(detail) %></li>
                            <% end %>
                          </ul>
                        <% elsif check[:details] %>
                           <p><%= h(check[:details]) %></p>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>

          <div class="footer">
            <div class="legend">
              <div class="legend-item">
                <strong>Severity:</strong> Upgrade blocking impact
              </div>
              <span style="color: #cbd5e0;">|</span>
              <div class="legend-item">
                <strong>Fix Effort:</strong> Implementation cost
              </div>
              <span style="color: #cbd5e0;">|</span>
              <div class="legend-item">
                <strong>Confidence:</strong> High: read from project files · Medium: pattern-based · Low: key input missing
              </div>
            </div>
            <p style="margin-top: 10px;">RailsPreFlight</p>
          </div>

        </body>
        </html>
      ERB

      ERB.new(template).result(binding)
    end

    private

    def rails_jump
      "#{@data[:current_rails] || 'unknown'} → #{@data[:target_rails]}"
    end

    def confidence_class(confidence)
      "badge-confidence-#{confidence.to_s.downcase}"
    end

    def occurrences_note(count)
      count ? " (#{count.to_i} occurrence#{'s' unless count == 1})" : ""
    end

    def section_id(title)
      "section-#{title.to_s.downcase.gsub(/[^a-z0-9]+/, '-')}"
    end

    def status_class(status)
      "badge-#{status}"
    end
  end
end
