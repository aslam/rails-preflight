# lib/rails_upgrade_audit/report_generator.rb
require 'erb'

module RailsUpgradeAudit
  class ReportGenerator
    def initialize(data)
      @data = data
      @generated_at = Time.now
    end

    def generate
      template = <<~ERB
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Rails Upgrade Audit Report</title>
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
            .meta { color: #666; font-size: 0.9em; margin-bottom: 20px; }
            .summary-card { background: #f0f4f8; border: 1px solid #d9e2ec; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
            .summary-title { font-size: 1.2em; font-weight: bold; margin-bottom: 15px; color: #102a43; border-bottom: 1px solid #bcccdc; padding-bottom: 10px; }
            .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
            .summary-item { background: white; padding: 15px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
            .summary-label { font-size: 0.8em; color: #486581; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 5px; }
            .summary-value { font-size: 1.4em; font-weight: bold; }
            .risk-high { color: #e53e3e; }
            .risk-medium { color: #dd6b20; }
            .risk-low { color: #38a169; }
            .blockers-list { margin: 0; padding-left: 20px; font-size: 0.9em; color: #e53e3e; }
          </style>
        </head>
        <body>
          <h1>Rails Upgrade Audit</h1>
          <div class="meta">
            Target Rails Version: <strong><%= @data[:target_rails] %></strong><br>
            Generated at: <%= @generated_at %>
          </div>

          <% if @data[:summary] %>
            <div class="summary-card">
              <div class="summary-title">Upgrade Readiness Summary</div>
              <div class="summary-grid">
                <div class="summary-item">
                  <div class="summary-label">Target Rails</div>
                  <div class="summary-value"><%= @data[:target_rails] %></div>
                </div>
                <div class="summary-item">
                  <div class="summary-label">Overall Risk</div>
                  <div class="summary-value risk-<%= @data[:summary][:overall_risk].downcase %>">
                    <%= @data[:summary][:overall_risk] %>
                  </div>
                </div>
                <div class="summary-item">
                  <div class="summary-label">Estimated Effort</div>
                  <div class="summary-value"><%= @data[:summary][:estimated_effort] %></div>
                </div>
                <div class="summary-item" style="grid-column: span 1 / -1;">
                  <div class="summary-label">Primary Blockers</div>
                  <% if @data[:summary][:primary_blockers].any? %>
                    <ul class="blockers-list">
                      <% @data[:summary][:primary_blockers].each do |blocker| %>
                        <li><%= blocker %></li>
                      <% end %>
                    </ul>
                  <% else %>
                    <div style="color: #38a169; font-weight: bold;">None detected! 🎉</div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <% @data[:results].each do |section| %>
            <div class="section">
              <div class="section-header">
                <span><%= section[:title] %></span>
                <span class="badge badge-<%= section[:status] %>"><%= section[:status].upcase %></span>
              </div>
              <div class="section-body">
                <% if section[:checks].empty? %>
                  <div class="item passed">No issues found.</div>
                <% else %>
                  <% section[:checks].each do |check| %>
                    <div class="item <%= check[:status] %>">
                      <strong><%= check[:message] %></strong>
                      <% if check[:details].is_a?(Array) %>
                        <ul>
                          <% check[:details].each do |detail| %>
                            <li><%= detail %></li>
                          <% end %>
                        </ul>
                      <% elsif check[:details] %>
                         <p><%= check[:details] %></p>
                      <% end %>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>

        </body>
        </html>
      ERB

      ERB.new(template).result(binding)
    end
  end
end
