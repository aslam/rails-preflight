require 'erb'
require_relative 'version'

module RailsPreflight
  class ReportGenerator
    include ERB::Util

    KIND_LABELS = { broken: "Broken", blocker: "Blocker", to_fix: "To fix", tip: "Tip", later: "Later" }.freeze
    KIND_CLASSES = { broken: "broken", blocker: "blocker", to_fix: "fix", tip: "tip", later: "later" }.freeze
    # Short label for the right-hand column when a finding has no link
    SECTION_LABELS = { "Gem Compatibility" => "Gems", "Private Gems" => "Gems", "Deprecation Warnings" => "Code",
                       "Configuration" => "Config", "Database Schema" => "Schema", "Ruby Version" => "Ruby",
                       "Docker Configuration" => "Docker", "Rails Version" => "Rails" }.freeze
    GEM_SECTIONS = ["Gem Compatibility", "Private Gems"].freeze
    EFFORTS = %w[low medium high].freeze
    HELP_URL = "https://syedaslam.com/work-with-me/".freeze
    REPO_URL = "https://github.com/aslam/rails-preflight".freeze

    # data: :results from the analyzers, :summary from SummaryCalculator, plus :app, :current_rails, :target_rails,
    # :ruby ([version, source]), :offline, :looked_up (gems asked about on rubygems.org) and :later_rails (known versions past the target).
    def initialize(data)
      @data = data
      @summary = data[:summary] || {}
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
          <title><%= h(@data[:app] || "Rails") %>: Rails <%= h(current_label) %> to <%= h(@data[:target_rails]) %></title>
          <style>
            /* An engineer's checklist on a sheet of paper. System fonts only: the report makes no network requests. */
            :root {
              --desk: #eceef1; --paper: #ffffff; --card: #fafbfc; --ink: #18202c; --muted: #5a6474; --rule: #d9dee5; --tint: #f1f5fa;
              --accent: #1f4f8f; --broken: #8a1c2b; --blocker: #b8322b; --fix: #9a5a00; --unknown: #64708a;
              --blocker-bg: #fbeceb;
              --display: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
              --sans: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
              --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
              color-scheme: light;
            }
            @media (prefers-color-scheme: dark) { :root {
              --desk: #0e1218; --paper: #161b23; --card: #1a202a; --ink: #e5e8ee; --muted: #9aa3b2; --rule: #2c3442; --tint: #1d2532;
              --accent: #8fb3ea; --broken: #f08a98; --blocker: #ff8a80; --fix: #f0b35a; --unknown: #a0a9bb; --blocker-bg: #2d1615;
              color-scheme: dark; } }

            * { box-sizing: border-box; }
            body { margin: 0; background: var(--desk); color: var(--ink); font: 15px/1.55 var(--sans); }
            .outer { padding: 24px 16px 64px; }
            .sheet { max-width: 960px; margin: 0 auto; background: var(--paper); padding: clamp(20px, 5vw, 48px); display: grid; gap: 36px; box-shadow: 0 1px 2px rgba(0,0,0,.06), 0 8px 30px rgba(20,30,50,.06); }
            a { color: var(--accent); }
            a:focus-visible, summary:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
            code { font: 0.88em var(--mono); }
            h1, h2, h3 { margin: 0; text-wrap: balance; }
            p { margin: 0; }

            header { display: grid; gap: 12px; }
            .tool { font: 500 12px var(--mono); color: var(--muted); letter-spacing: 0.03em; }
            h1 { font: 500 clamp(30px, 5.4vw, 46px)/1.08 var(--display); letter-spacing: -0.01em; }
            h1 .app { color: var(--accent); }
            h1 .to { color: var(--muted); }
            .verdict { font: 400 19px/1.45 var(--display); max-width: 62ch; }
            .facts { display: flex; flex-wrap: wrap; gap: 4px 18px; color: var(--muted); font-size: 13px; }
            .facts b { color: var(--ink); font-weight: 500; }

            .counts { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); border-block: 1px solid var(--rule); }
            .count { padding: 14px 16px 14px 0; display: grid; gap: 2px; align-content: start; text-decoration: none; color: inherit; }
            .count + .count { padding-left: 16px; border-left: 1px solid var(--rule); }
            .count:hover .l { text-decoration: underline; }
            .count .n { font: 600 30px/1 var(--mono); color: var(--c); font-variant-numeric: tabular-nums; }
            .count.zero .n { color: var(--muted); }
            .count .l { font-weight: 600; font-size: 13px; }
            .count .d { font-size: 12px; color: var(--muted); }
            @media (max-width: 640px) { .counts { grid-template-columns: repeat(2, minmax(0, 1fr)); } .count:nth-child(3) { padding-left: 0; border-left: 0; } .count:nth-child(n+3) { border-top: 1px solid var(--rule); } }

            h2 { font: 600 12.5px var(--mono); text-transform: uppercase; letter-spacing: 0.09em; color: var(--muted); }
            .block { display: grid; gap: 12px; }

            .route-box { border: 1px solid var(--rule); border-radius: 6px; }
            .route-scroll { overflow-x: auto; }
            .route { display: grid; grid-template-columns: repeat(var(--stops), minmax(88px, 1fr)); min-width: calc(var(--stops) * 90px); padding: 18px 8px 12px; }
            .stop { display: grid; justify-items: center; align-content: start; gap: 6px; position: relative; text-decoration: none; color: inherit; }
            .stop::before { content: ""; position: absolute; top: 9px; left: -50%; width: 100%; height: 2px; background: var(--rule); }
            .stop:first-child::before { display: none; }
            .dot { width: 20px; height: 20px; border-radius: 50%; background: var(--paper); border: 2px solid var(--muted); z-index: 1; }
            .stop.now .dot { background: var(--ink); border-color: var(--ink); }
            .stop.has .dot { border-color: var(--blocker); background: var(--blocker-bg); }
            .stop.target .v { text-decoration: underline 2px; text-underline-offset: 4px; }
            .stop.ahead { opacity: 0.6; }
            .stop.ahead .dot { border-style: dashed; }
            .stop.ahead::before { background: repeating-linear-gradient(90deg, var(--rule) 0 6px, transparent 6px 10px); }
            .stop .v { font: 600 15px var(--mono); }
            .stop .b { font-size: 12px; color: var(--muted); font-variant-numeric: tabular-nums; text-align: center; }
            .stop.has .b { color: var(--blocker); font-weight: 500; }
            .route-note { font-size: 12px; color: var(--muted); padding: 0 14px 12px; }

            .table-scroll { overflow-x: auto; }
            table.plan { border-collapse: collapse; width: 100%; min-width: 600px; font-size: 14px; }
            .plan th { text-align: left; font: 600 11px var(--mono); text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); padding: 8px 10px; border-bottom: 2px solid var(--ink); }
            .plan td { padding: 11px 10px; border-bottom: 1px solid var(--rule); vertical-align: top; }
            .plan td:first-child { font: 500 14px var(--mono); white-space: nowrap; }
            .plan td:first-child a { color: inherit; }
            .plan .num { text-align: right; font-variant-numeric: tabular-nums; }
            .plan tr.target td { background: var(--tint); }
            .plan tr.later td { color: var(--muted); }
            .plan td:last-child { white-space: nowrap; }
            .plan .ruby { display: block; margin-top: 3px; font-size: 12.5px; color: var(--accent); font-weight: 500; }
            .effort { display: inline-flex; gap: 3px; vertical-align: middle; margin-right: 6px; }
            .effort i { width: 9px; height: 9px; border-radius: 2px; background: var(--rule); }
            .effort.low i:nth-child(-n+1), .effort.medium i:nth-child(-n+2), .effort.high i:nth-child(-n+3) { background: var(--ink); }

            .step { background: var(--card); border: 1px solid var(--rule); border-radius: 6px; scroll-margin-top: 16px; }
            .step.ahead-card { border-style: dashed; }
            .step-head { display: flex; flex-wrap: wrap; align-items: baseline; justify-content: space-between; gap: 6px 16px; padding: 11px 16px; border-bottom: 1px solid var(--rule); }
            .step-head:last-child { border-bottom: 0; }
            .step-head h3 { font: 600 17px var(--mono); }
            .ahead-card .step-head h3 { color: var(--muted); }
            .step-head .tag { font-size: 12px; color: var(--muted); }
            .rubynote { display: flex; gap: 10px; align-items: baseline; padding: 9px 16px; font-size: 13px; color: var(--muted); border-bottom: 1px solid var(--rule); }
            .rubynote:last-child { border-bottom: 0; }
            .rubynote .k { font: 600 11px var(--mono); text-transform: uppercase; letter-spacing: 0.06em; min-width: 40px; color: var(--accent); }
            ul.rows { list-style: none; margin: 0; padding: 0; }
            .row { display: grid; grid-template-columns: 88px minmax(0, 1fr) auto; gap: 4px 14px; padding: 11px 16px; border-bottom: 1px solid var(--rule); align-items: start; }
            .row:last-child { border-bottom: 0; }
            .kind { font: 600 10.5px/2 var(--mono); text-transform: uppercase; letter-spacing: 0.05em; color: var(--c); }
            .kind::before { content: ""; display: inline-block; width: 8px; height: 8px; border-radius: 2px; background: var(--c); margin-right: 6px; }
            .msg { min-width: 0; overflow-wrap: anywhere; }
            .meta { display: flex; flex-wrap: wrap; gap: 2px 12px; font-size: 12px; color: var(--muted); margin-top: 3px; font-variant-numeric: tabular-nums; }
            .cite { font: 12px var(--mono); white-space: nowrap; color: var(--muted); }
            a.cite { color: var(--accent); }
            .empty { padding: 12px 16px; color: var(--muted); font-size: 14px; }
            @media (max-width: 640px) { .row { grid-template-columns: minmax(0, 1fr); } .cite { white-space: normal; } }
            .broken { --c: var(--broken); } .blocker { --c: var(--blocker); } .fix { --c: var(--fix); } .unknown { --c: var(--unknown); }
            .tip { --c: var(--accent); } .later { --c: var(--muted); }

            /* The meta line is the toggle for its files */
            details.occ { margin-top: 3px; }
            details.occ > summary { list-style: none; cursor: pointer; display: inline-flex; flex-wrap: wrap; gap: 2px 12px; font-size: 12px; color: var(--accent); font-variant-numeric: tabular-nums; }
            details.occ > summary::-webkit-details-marker { display: none; }
            details.occ > summary::before { content: "▸"; transition: transform .15s; }
            details.occ[open] > summary::before { transform: rotate(90deg); }
            @media (prefers-reduced-motion: reduce) { details.occ > summary::before { transition: none; } }
            .snip { overflow: auto; max-height: 360px; margin-top: 8px; border: 1px solid var(--rule); border-radius: 6px; background: var(--paper); }
            .snip table { border-collapse: collapse; font: 12px/1.5 var(--mono); width: 100%; }
            .snip td { padding: 4px 10px; border-bottom: 1px solid var(--rule); white-space: nowrap; }
            .snip td.line { color: var(--muted); text-align: right; }
            .snip tr:last-child td { border-bottom: 0; }

            .limits { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1px; background: var(--rule); border: 1px solid var(--rule); border-radius: 6px; overflow: hidden; }
            .limit { background: var(--card); padding: 14px 16px; display: grid; gap: 6px; align-content: start; }
            .limit h3 { font: 600 14.5px var(--sans); }
            .limit p { font-size: 13.5px; color: var(--muted); }
            .limit .next { color: var(--ink); }
            .limit .next::before { content: "→ "; color: var(--accent); }
            .names { font: 12px/1.7 var(--mono); color: var(--ink); overflow-wrap: anywhere; }
            @media (max-width: 640px) { .limits { grid-template-columns: minmax(0, 1fr); } }

            footer { border-top: 1px solid var(--rule); padding-top: 18px; display: grid; gap: 12px; font-size: 13px; color: var(--muted); }
            footer dl { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 4px 14px; margin: 0; }
            footer dt { font-weight: 600; color: var(--ink); }
            footer dd { margin: 0; }
            .sig { display: flex; flex-wrap: wrap; gap: 4px 18px; }

            @media print {
              :root { --desk: #fff; --paper: #fff; --card: #fff; --ink: #18202c; --muted: #5a6474; --rule: #d9dee5; --tint: #f1f5fa;
                --accent: #1f4f8f; --broken: #8a1c2b; --blocker: #b8322b; --fix: #9a5a00; --unknown: #64708a; --blocker-bg: #fbeceb; color-scheme: light; }
              /* Dots, effort bars and markers are backgrounds, which browsers drop when printing */
              * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
              body { font-size: 10pt; }
              .outer { padding: 0; }
              .sheet { box-shadow: none; padding: 0 2mm; max-width: none; gap: 24px; }
              details.occ > summary { color: var(--muted); }
              details.occ > summary::before { content: ""; }
              details.occ > :not(summary) { display: none; }
              .route-scroll { overflow: visible; }
              .route, table.plan { min-width: 0; }
              .step-head, .rubynote, .row, .plan tr, .limit, .counts, .route-box { break-inside: avoid; }
              a { color: inherit; text-decoration: none; }
              @page { size: A4; margin: 14mm; }
            }
          </style>
        </head>
        <body>
        <div class="outer">
        <article class="sheet">
          <header>
            <div class="tool">rails-preflight <%= h(VERSION) %> · <%= h(@generated_at.strftime("%-d %b %Y, %H:%M")) %></div>
            <h1><% if @data[:app] %><span class="app"><%= h(@data[:app]) %>:</span> <% end %>Rails <%= h(current_label) %> <span class="to">to</span> <%= h(@data[:target_rails]) %></h1>
            <p class="verdict"><%= h(@summary[:verdict]) %></p>
            <div class="facts">
              <% ruby, source = @data[:ruby] %>
              <% if ruby %><span>Ruby <b><%= h(ruby) %></b> (<%= h(source) %>)</span><% end %>
              <% if @data[:offline] %><span><b>Offline</b>: rubygems.org not asked</span><% end %>
              <% if @data[:looked_up] %><span>Online: <b><%= @data[:looked_up] %></b> gems looked up on rubygems.org</span><% end %>
            </div>
          </header>

          <nav class="counts" aria-label="Totals">
            <% count_tiles.each do |css, n, label, caption, href| %>
              <a class="count <%= css %><%= " zero" if n.zero? %>" href="<%= href %>"><span class="n"><%= n %></span><span class="l"><%= h(label) %></span><span class="d"><%= h(caption) %></span></a>
            <% end %>
          </nav>

          <section class="block" aria-labelledby="plan-h">
            <h2 id="plan-h">Route and plan</h2>
            <div class="route-box">
              <div class="route-scroll">
                <div class="route" style="--stops: <%= route_stops.size %>">
                  <% route_stops.each do |css, version, note, href| %>
                    <a class="stop <%= css %>" href="<%= href %>"><span class="dot"></span><span class="v"><%= h(version) %></span><span class="b"><%= h(note) %></span></a>
                  <% end %>
                </div>
              </div>
              <% if route_ahead.any? %>
                <p class="route-note">Checked through <%= h(@data[:target_rails]) %>. Faded stops count code that later versions remove, found in the same scan; gem limits past <%= h(@data[:target_rails]) %> aren't checked. Run <code>rails-preflight <%= h(route_ahead.last) %></code> for the full route.</p>
              <% end %>
            </div>
            <div class="table-scroll">
              <table class="plan">
                <thead><tr><th>Step</th><th>What to do</th><th class="num">Blockers</th><th>Effort</th></tr></thead>
                <tbody>
                  <% if before.any? %>
                    <tr><td><a href="#before"><%= h(@data[:current_rails] ? "Now, on #{minor(@data[:current_rails])}" : "Before you start") %></a></td><td><%= h(what_to_do(before)) %></td><td class="num"><%= blockers_in(before) %></td><td><%= effort_html(before) %></td></tr>
                  <% end %>
                  <% steps.each do |step| %>
                    <tr<%= ' class="target"' if step.equal?(steps.last) %>><td><a href="#<%= step_id(step[:version]) %>">→ <%= h(step[:version]) %></a></td><td><%= h(what_to_do(step[:checks])) %><span class="ruby"><%= h(step[:ruby]) %></span></td><td class="num"><%= blockers_in(step[:checks]) %></td><td><%= effort_html(step[:checks]) %></td></tr>
                  <% end %>
                  <% if ahead.any? %>
                    <% later = ahead.values.flatten %>
                    <tr class="later"><td><a href="#ahead-h">Optional</a></td><td><%= h("Start on what later versions remove while you're in the code: #{what_to_do(later)}") %></td><td class="num">–</td><td><%= effort_html(later) %></td></tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>

          <section class="block" aria-labelledby="steps-h">
            <h2 id="steps-h">Steps</h2>
            <% if before.any? %>
              <article class="step" id="before">
                <div class="step-head"><h3>Before you start</h3><% if @data[:current_rails] %><span class="tag">on Rails <%= h(minor(@data[:current_rails])) %></span><% end %></div>
                <ul class="rows"><% before.each do |entry| %><%= row_html(entry) %><% end %></ul>
              </article>
            <% end %>
            <% steps.each do |step| %>
              <article class="step" id="<%= step_id(step[:version]) %>">
                <div class="step-head"><h3><%= h(step[:from] ? "#{step[:from]} → #{step[:version]}" : "Rails #{step[:version]}") %></h3><span class="tag"><%= h(blocker_tag(step[:checks])) %></span></div>
                <div class="rubynote"><span class="k">Ruby</span><span><%= h(step[:ruby]) %></span></div>
                <% if step[:checks].any? %>
                  <ul class="rows"><% step[:checks].each do |entry| %><%= row_html(entry) %><% end %></ul>
                <% end %>
              </article>
            <% end %>
            <% if steps.empty? %>
              <p class="empty">Already on Rails <%= h(@data[:target_rails]) %>: no upgrade steps.</p>
            <% end %>
          </section>

          <% if ahead.any? %>
            <section class="block" aria-labelledby="ahead-h">
              <h2 id="ahead-h">Ahead of <%= h(@data[:target_rails]) %></h2>
              <% ahead.each do |version, entries| %>
                <article class="step ahead-card" id="<%= ahead_id(version) %>">
                  <div class="step-head"><h3><%= h(version) %></h3><span class="tag">not needed for <%= h(@data[:target_rails]) %></span></div>
                  <ul class="rows"><% entries.each do |entry| %><%= row_html(entry, :later) %><% end %></ul>
                </article>
              <% end %>
              <% clear = route_ahead - ahead.keys %>
              <% if clear.any? %><p class="empty">Nothing in the code is removed by <%= h(clear.join(" or ")) %>.</p><% end %>
            </section>
          <% end %>

          <section class="block" id="cant-see" aria-labelledby="cant-h">
            <h2 id="cant-h">What this report can't see</h2>
            <div class="limits">
              <% @summary.fetch(:cant_see, []).each do |entry| %>
                <div class="limit">
                  <h3><%= h(entry[:title] || entry[:section]) %></h3>
                  <p><%= code_html(entry[:message]) %></p>
                  <% names = Array(entry[:names]) %>
                  <% if names.any? %><p class="names"><%= h(names.join(" · ")) %></p><% end %>
                  <% if (next_step = cant_see_next(entry)) %><p class="next"><%= next_step %></p><% end %>
                </div>
              <% end %>
              <div class="limit">
                <h3>Behavior changes</h3>
                <p>Some changes leave no telltale line: new framework defaults and changed query behavior.</p>
                <p class="next">Run the test suite with <code>config.active_support.deprecation = :raise</code>.</p>
              </div>
              <div class="limit">
                <h3>Multi-line code and test coverage</h3>
                <p>The scan matches single lines and never runs the app, so a call split across lines is missed, and it can't tell how much of the app the tests cover.</p>
                <p class="next">Treat a clean step as "nothing found", not "nothing there".</p>
              </div>
            </div>
          </section>

          <footer>
            <dl>
              <dt>Confidence</dt><dd><%= h(confidence_line) %></dd>
              <dt>Sources</dt><dd>Removed APIs link to the Rails release notes for the version that removed them. Gem limits come from <code>Gemfile.lock</code> or the gem's README.</dd>
            </dl>
            <div class="sig">
              <span>Made with <a href="<%= REPO_URL %>">rails-preflight</a>. Run it again after each step.</span>
              <span>Need a hand with the upgrade? <a href="<%= HELP_URL %>">syedaslam.com/work-with-me</a></span>
            </div>
          </footer>
        </article>
        </div>
        </body>
        </html>
      ERB

      ERB.new(template).result(binding)
    end

    private

    def before
      @summary.fetch(:before, [])
    end

    def steps
      @summary.fetch(:steps, [])
    end

    def ahead
      @summary.fetch(:ahead, {})
    end

    def current_label
      @data[:current_rails] || "unknown"
    end

    def minor(version)
      version.to_s.split(".").first(2).join(".")
    end

    def count(key)
      @summary.fetch(key, []).size
    end

    def step_id(version)
      "s#{version.to_s.tr('.', '-')}"
    end

    def ahead_id(version)
      "a#{version.to_s.tr('.', '-')}"
    end

    def blockers_in(entries)
      entries.count { |entry| entry[:kind] == :blocker }
    end

    def count_tiles
      later = ahead.values.sum(&:size)
      now = count(:to_fix) - later
      first_blocked = steps.find { |step| blockers_in(step[:checks]).positive? }
      [
        ["broken", count(:broken), "Already broken", "Removed before #{@data[:current_rails] ? minor(@data[:current_rails]) : 'your Rails'}: fails when it runs", "#before"],
        ["blocker", count(:blockers), "Blockers", "Must be fixed for #{@data[:target_rails]} to work", first_blocked ? "##{step_id(first_blocked[:version])}" : "#steps-h"],
        ["fix", count(:to_fix), "To fix", later.positive? ? "#{now} now, #{later} before later versions" : "Will warn or break along the way", now.positive? ? "#before" : "#ahead-h"],
        ["unknown", count(:unknowns), "Couldn't check", "Review by hand", "#cant-see"]
      ]
    end

    # Known versions past the target, plus any version a finding names
    def route_ahead
      @route_ahead ||= (Array(@data[:later_rails]) | ahead.keys).sort_by { |version| Gem::Version.new(version) }
    end

    # [css, version, note, href] for each stop: where the app is, each step, then later versions faded.
    def route_stops
      stops = []
      stops << ["now", minor(@data[:current_rails]), "you are here", before.any? ? "#before" : "#steps-h"] if @data[:current_rails]
      steps.each do |step|
        blockers = blockers_in(step[:checks])
        css = [("has" if blockers.positive?), ("target" if step.equal?(steps.last))].compact.join(" ")
        stops << [css, step[:version], blockers.zero? ? "no blockers" : "#{blockers} #{blockers == 1 ? 'blocker' : 'blockers'}", "##{step_id(step[:version])}"]
      end
      route_ahead.each do |version|
        seen = ahead.fetch(version, []).size
        stops << ["ahead", version, seen.zero? ? "none seen" : "#{seen} seen ahead", seen.zero? ? "#ahead-h" : "##{ahead_id(version)}"]
      end
      stops
    end

    # A short summary of a step's work, by kind and area.
    def what_to_do(entries)
      work = entries.reject { |entry| entry[:kind] == :tip }
      return "Nothing found." if work.empty?

      broken, rest = work.partition { |entry| entry[:kind] == :broken }
      gems, rest = rest.partition { |entry| GEM_SECTIONS.include?(entry[:section]) }
      code, rest = rest.partition { |entry| entry[:section] == "Deprecation Warnings" }
      lines = code.sum { |entry| entry[:files].size }
      parts = []
      parts << "#{broken.size} already broken" if broken.any?
      parts << plural(gems.size, "gem") if gems.any?
      parts << "#{plural(code.size, 'removed API')} (#{plural(lines, 'line')})" if code.any?
      parts << "#{rest.size} more (#{rest.map { |entry| SECTION_LABELS.fetch(entry[:section], entry[:section]) }.uniq.join(', ')})" if rest.any?
      "#{parts.join(', ')}."
    end

    def plural(n, word)
      "#{n} #{word}#{'s' unless n == 1}"
    end

    def blocker_tag(entries)
      blockers = blockers_in(entries)
      return "nothing to fix" if entries.empty?

      blockers.zero? ? "no blockers" : plural(blockers, "blocker")
    end

    # The highest fix effort among the step's findings; relative only, never hours.
    def effort_html(entries)
      level = entries.filter_map { |entry| EFFORTS.index(entry[:fix_effort].to_s) }.max
      return "–" unless level

      %(<span class="effort #{EFFORTS[level]}"><i></i><i></i><i></i></span>#{EFFORTS[level].capitalize})
    end

    # One finding: kind, message with its meta line (the toggle for its files), and a link or its area.
    def row_html(entry, kind = entry[:kind])
      css = KIND_CLASSES.fetch(kind, "unknown")
      %(<li class="row #{css}"><span class="kind">#{h(KIND_LABELS.fetch(kind, kind.to_s))}</span>) +
        %(<div class="msg">#{code_html(entry[:message])}#{occurrences_html(entry)}</div>#{cite_html(entry)}</li>)
    end

    # Code matches list file, line and snippet; gem usage lists files. Everything is escaped.
    def occurrences_html(entry)
      files = Array(entry[:files])
      lines = files.select { |hit| hit[:line] }
      meta = []
      meta << occurrence_count(lines) if lines.any?
      meta << plural(files.map { |hit| hit[:file] }.uniq.size, "file") if files.any?
      meta << "Fix: #{entry[:fix_effort]}" if entry[:fix_effort] && entry[:fix_effort].to_s != "unknown"
      return "" if meta.empty?

      spans = meta.map { |part| "<span>#{h(part)}</span>" }.join
      return %(<div class="meta">#{spans}</div>) if files.empty?

      rows = files.map do |hit|
        hit[:line] ? %(<tr><td>#{h(hit[:file])}</td><td class="line">#{h(hit[:line])}</td><td>#{h(hit[:snippet])}</td></tr>) : %(<tr><td>#{h(hit[:file])}</td></tr>)
      end
      %(<details class="occ"><summary>#{spans}</summary><div class="snip"><table>#{rows.join}</table></div></details>)
    end

    def occurrence_count(hits)
      total = hits.size
      test = hits.count { |hit| hit[:test] }
      text = plural(total, "occurrence")
      return text if test.zero?
      return "#{text}, #{total == 1 ? 'in a test' : 'all in tests'}" if test == total

      "#{text} (#{total - test} app, #{test} test)"
    end

    # The release notes or source a finding cites; its area when it has none. Links render https only.
    def cite_html(entry)
      url = entry[:source] if entry[:source].to_s.start_with?("https://")
      return %(<span class="cite">#{h(SECTION_LABELS.fetch(entry[:section], entry[:section]))}</span>) unless url

      notes = url[%r{guides\.rubyonrails\.org/(\d+)_(\d+)_release_notes}] && "#{$1}.#{$2} notes"
      label = notes || (url.include?("guides.rubyonrails.org") ? "Guide" : "Source")
      %(<a class="cite" href="#{h(url)}" target="_blank" rel="noopener">#{label} ↗</a>)
    end

    # Escaped, with 'quoted' names set as code. An apostrophe inside a word (doesn't) isn't a quote.
    def code_html(text)
      h(text).gsub(/(?<![\w&;])&#39;(.+?)&#39;(?![\w&])/) { "<code>#{$1}</code>" }
    end

    # A titled entry (the rubygems.org lookup) says what to do in its own message.
    def cant_see_next(entry)
      return if entry[:title]

      case entry[:section]
      when "Private Gems" then "Check each gemspec's Rails dependency, and bump them in the same step."
      when "Gem Compatibility"
        %(<a href="https://railsbump.org">RailsBump</a> or next_rails' <code>bundle_report compatibility</code> show which releases support #{h(@data[:target_rails])}.)
      end
    end

    def confidence_line
      by_level = Array(@data[:results]).select { |section| section[:confidence] }.group_by { |section| section[:confidence].to_sym }
      { high: "read from project files", medium: "pattern matches", low: "a key input is missing" }.filter_map do |level, meaning|
        sections = by_level[level]
        "#{level.to_s.capitalize}, #{meaning}: #{sections.map { |section| section[:title] }.join(', ')}." if sections
      end.join(" ")
    end
  end
end
