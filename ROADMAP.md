# Roadmap

_Last updated: 2026-10-09_

rails-preflight answers one question about a Rails app: **what stands between this app and Rails X, and how sure are we?** Everything below makes that answer more correct, easier to read, or broader.

## Principles

- **Read-only.** Never modifies the app. The only file it writes is the report.
- **Static.** Reads files. Doesn't run the app or its tests. Asks rubygems.org about public gems by default, never about private ones; `--offline` makes it fully static (decided 2026-10-07; next_rails does the same).
- **Deterministic.** Same app, same report.
- **Honest.** Every number in the report traces back to a finding. When we can't tell, we say so instead of guessing.

## Shipped

**Reading the app**
- Current Rails from `Gemfile.lock`, shown as `current → target`; the target defaults to the next Rails minor, with a hint pointing to the full path
- Ruby from `.ruby-version`, `Gemfile.lock` or the Dockerfile, checked against each Rails from 5.0 to 8.1; Ruby and Node end-of-life
- Stops with a clear message when the directory isn't a Rails app, or when the current Rails is unknown and no target is given

**Gems**
- Private gems from `Gemfile.lock` and the Gemfile's `source` blocks, `source:` options and `eval_gemfile` files, read but never evaluated; rubygems.org is asked only about gems neither file places
- Locked gems whose declared Rails requirement excludes a step block that step
- `database/gems.yml`: 8 gems whose limits only a README states, each with its source and a count of the files that use it; database adapter versions per Rails; gems `rails` stops depending on (sprockets-rails in 7.0), flagged only when the app uses them
- Stale gems (online): public gems that depend on Rails with no release since before the target Rails shipped

**Code and config**
- 118 deprecation rules, at least one removal per Rails step from 5.1 to 8.1, each cited to the release notes and linked to its guide
- Scans `.rb`, `.erb` and `.rake` under `app/`, `config/`, `db/`, `lib/`, `test/` and `spec/`; rules can opt into scripts and CI config (removed rake tasks) or config YAML (`cable.yml`, `database.yml`, `storage.yml`), scope themselves with `paths:`, and require a receiver with `needs_receiver_in:` (a bare `errors` in a helper is a local) or `skip_bare_if_local:` (a file that assigns `errors` or takes it as a parameter)
- A blocker when this upgrade removes the API; "already broken" when it was removed at or before the current Rails, listed first
- Commented-out code is skipped; snippets hide values on lines that name a secret, token or password
- `config.load_defaults` missing or behind; Docker checks (EOL base image, locale, tzdata, Alpine build deps, Alpine/OpenSSL 3); schema charset and integer IDs

**Report**
- Single-file HTML report (design A): verdict, counts, route with later versions faded, plan table, one card per step, what the report can't see; dark mode and print styles, no network requests
- Upgrade path with one step per Rails minor, the Ruby range each needs and the APIs to fix at each; says which step to upgrade Ruby on, and to what
- Terminal summary for SSH sessions and CI logs; related tools (next_rails, RailsBump, Brakeman, rubocop-rails) in the README and footer

**Project**
- Every deprecation rule has a sample line in the test suite, and its replacement is checked not to trigger it; CI on Ruby 2.7 to 4.0
- Accurate README, CHANGELOG, MIT LICENSE, gemspec that packages only what the gem needs; `rails_preflight` was free on rubygems.org on 2026-10-07

## Now

Redmine, Mastodon, Discourse and Forem are done (item 1 below). Next: grow the gem list from what they found, or one more app on a different stack.

## First public release

The bar is a report that holds up on real apps, not an empty roadmap. In order:

1. **Run it on real apps.** Check out old tagged versions of open-source Rails apps, run the report and review every finding. Rules are tested against hand-written sample lines, and false positives are what lose trust fastest.
   - 2026-10-03, two private apps: a Rails 5.2 app (1,923 files; 7 blockers, all real) and a Rails 8.1 app (no findings, even when scanned as if upgrading from 5.0). Fixed a false positive (hash-rocket keyword args in controller tests) and a bogus upgrade step when already on the target.
   - 2026-10-05, the 5.2 app: its Bundler 1.17 lockfile mixes rubygems.org and a private registry in one section. The rubygems.org lookup took minutes and missed 5 of its 11 private gems (private forks under public names); reading the Gemfile's source blocks finds all 11 in about a second.
   - 2026-10-07, Redmine 4.0.0 (Rails 5.2) and 5.0.0 (6.1) → 8.1, with lockfiles from `bundle lock` (Redmine commits none). 28 findings checked against the source and against Redmine 6.0 on Rails 7.2, where any hit still present is suspect. Fixed two false positives: bare `errors.each |a, b|` on an Array in a helper, and sprockets-rails flagged for an app that never loads it. "Already broken" was right every time.
   - 2026-10-07, Mastodon: ten releases, each one before a Rails bump run to the Rails the next one moved to (5.1 → 8.1), with their committed lockfiles. All 17 gem blockers and every removed-API blocker were fixed in the next release. Fixed three false positives: Chewy `tokenizer:` strings, a service's own `destroy_all(x)`, and an app method named `image_alt`.
   - 2026-10-07, Discourse: fourteen releases, 5.1 → 8.1. It locks railties, not rails, which the tool reads fine. All 8 gem blockers were fixed in the next release. Fixed false positives: `errors` as a local Hash in a controller, `lib/` and specs (rules now skip a bare `errors` in a file that assigns it or takes it as a parameter), a local named `update_attributes`, and `class_name: Constant` in a non-association DSL. Real "already broken" finds: `render nothing: true` since 5.1, and `clear_active_connections!` in a dev script since 7.2. Left: Onebox's `errors` is a Hash set in another file, so three hits stay; a per-file scan can't see it.
   - 2026-10-07, Forem (dev.to): the commit before and after each of its seven Rails upgrades, 5.1 → 8.0, found by bisecting `Gemfile.lock`. All 3 gem blockers were fixed in the upgrade commit. Fixed false positives: `AhoyEmail.secret_token` (a gem's setting), the new `connection_handler` API mocked as `receive(:clear_active_connections!)`, `render file: "public/404.html"` (paths that exist from the app root still render on 6.1+), and setting names inside `respond_to?(:x)` guards. Real "already broken" finds: `render text:` in an API controller since 5.1, and `ActiveRecord::Base.timestamped_migrations` in a generator since 7.1. Left: a removed setting in the `else` branch of a `respond_to?` guard is reported as dead code, which it is, but on purpose.
2. **Grow the gem list** in `database/gems.yml` from what the runs find, citing a README, deprecation notice or Rails source for each entry. The release notes 5.1 → 8.1 have been read in full and name few gems.
   - 2026-10-07, the private 5.2 app → 7.0: five locked gems cap Rails (responders and active_record_replica below 6.0, acts-as-taggable-on below 6.1, activeresource and acts_as_paranoid below 7.0), and protected_attributes_continued blocks 7.0 across 131 files.
3. **Publish 0.1.0.** Tag `v0.1.0`, `gem push`, make the repo public.

Not needed for the first release: `structure.sql` and anything under Maybe.

## After the release: the report and its formats

Decided 2026-10-07. Every format renders one structured set of findings; none parses another's output. In order:

1. **Findings model and HTML redesign.** Done: the HTML since 2026-10-08, the findings model since 2026-10-09 (the parts are documented in `summary_calculator.rb`). Findings carry their parts (gem, versions, limit, step, `removed_in`, files with line and snippet, citation, confidence), not only a finished sentence. The HTML follows design A (mockup: claude.ai/artifact/8HHnsQ12mV4exU6wSVJRwY):
   - Title `app: Rails X to Y` and a one-sentence verdict generated from the findings
   - Counts, then the route: one stop per Rails minor, blocker counts, Ruby upgrades marked; past the target, faded "ahead" stops count code that later versions remove (gem limits past the target aren't checked)
   - Plan table under the route: step, what to do, blockers, relative effort (never hours)
   - One card per step; each finding's meta line ("7 occurrences, all in tests · 2 files") expands to file, line and snippet
   - "What this report can't see" last: private gems and stale gems by name, behavior changes, multi-line code and test coverage, each with what to do instead (RailsBump, next_rails, rubocop-rails named where they answer the gap)
   - Footer: confidence, sources, the repo, one help line to syedaslam.com/work-with-me. Neutral otherwise; the free report is complete
   - Dark mode follows the OS, no toggle. `@media print`: A4, light colors, file lists hidden, `print-color-adjust: exact` (dots, effort bars and markers are backgrounds, which browsers drop when printing)
2. **JSON** with a versioned schema (`"schema": 1`) and stable rule ids; `--format json` prints JSON on stdout and progress on stderr. `--fail-on blockers|broken` sets the exit code, so CI can gate on it.
3. **Markdown**, done 2026-10-09 (`--format markdown`), which is also the format for LLMs and coding agents: ordered by step, `file:line` and the replacement for each finding, a short header telling an agent to take one step at a time, run the tests after each, and leave "ahead" and "can't see" items alone. Pastes into issues and PRs as is.
4. **Console** as a text version of the HTML: verdict, a one-line route, counts, blockers by step, the report's path.

Not doing for now: PDF generation (headless Chrome or a layout library is a heavy dependency for what printing the HTML already does; a `--pdf` that uses an installed Chrome can come later if asked), and an MCP server (an agent can read the Markdown).

## Next: cover more of the upgrade

- **Deepen the deprecation rules.** Every hop has at least one rule, but the guides list dozens of removals per version. Add the ones that are statically detectable and plausible in app code, applying only those whose `removed_in` falls within the jump. Link each rule to the Rails guides, API docs or a commit, not blog posts, which rot.
- **Support `structure.sql`** in the database checks, not only `db/schema.rb`.
- **Check each gem's declared Rails support** on rubygems.org (skipped with `--offline`): read the Rails dependency its released versions declare, and report "devise 4.7 caps Rails below 6.1; 4.9 allows 7.2, bump it first". Never query gems from a non-rubygems.org source. Overlaps next_rails' `bundle_report compatibility`; the value is one report. Missing upper bounds read as compatible, so the curated list still matters.
- **Parse the Gemfile with Ripper** instead of line by line, if real Gemfiles hit what the line reader misses: one-line `do … end` and `{ … }` source blocks (these fall back to the rubygems.org lookup) and `x = if … end` inside a source block (closes it early, so its later gems count as public).

## Later

- **`rails-ujs` after 8.1.** The 7.2 notes list "Remove deprecated @rails/ujs", but that was the JS source and build tooling (rails/rails#50535): `rails-ujs.js` still ships in actionview through `8-1-stable`, so `//= require rails-ujs` works. It is gone on `main`; when that Rails ships, add a rule, which needs `.js` scanning under `app/assets` and `app/javascript`.
- Scope flags such as `--exclude-tests`
- Cross-check Ruby version sources (`.ruby-version` vs Dockerfile vs CI config)

## Maybe (to discuss)

- **Changelog database.** Build a database of Rails changelog entries and show the ones relevant to the app in the report. Open question: how much of this the deprecation rules already cover.
- **Upgrade diagram.** A roadmap.sh-style diagram of the actual steps for each upgrade, including when to run `app:update`, etc.
- **Migration risk in the report.** Some findings can only be fixed with a migration that rewrites a table: integer IDs → bigint, utf8mb3 → utf8mb4. Flag the risk that fix carries next to the finding: table rewrite and locking, uniqueness races when adding unique indexes, a suggested rollout order, and Rails/Postgres/MySQL version caveats. Optionally do the same for migrations in `db/migrate` newer than the schema version. Still read-only: the report flags the risk, it doesn't write or run migrations.

## Not doing

- Automatic fixes, migrations, or code rewriting
- Running the app or its test suite
- One-click upgrades
