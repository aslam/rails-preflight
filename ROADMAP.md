# Roadmap

_Last updated: 2026-10-05_

rails-preflight answers one question about a Rails app: **what stands between this app and Rails X, and how sure are we?** Everything below makes that answer more correct, easier to read, or broader.

## Principles

- **Read-only.** Never modifies the app. The only file it writes is the report.
- **Static.** Reads files. Doesn't run the app or its tests. Asks rubygems.org about public gems by default, never about private ones; `--offline` makes it fully static (decided 2026-10-07; next_rails does the same).
- **Deterministic.** Same app, same report.
- **Honest.** Every number in the report traces back to a finding. When we can't tell, we say so instead of guessing.

## Shipped

- Current Rails version from `Gemfile.lock`, shown as `current → target` in the report and upgrade path
- Target defaults to the next Rails minor after the app's, with a hint pointing to the full path; stops when the current Rails is unknown, exits when already on the newest known
- Ruby compatibility per target Rails (5.0 – 8.1), read from `.ruby-version`, `Gemfile.lock`, or the Dockerfile
- EOL checks for Ruby and Node
- Private gem detection from `Gemfile.lock` and the Gemfile's `source` blocks, `source:` options and `eval_gemfile` files, read but never evaluated; a rubygems.org lookup only for gems neither file places, skipped with `--offline`
- Gem compatibility: locked gems whose declared Rails requirement excludes a hop block that hop (from `Gemfile.lock`, offline); a curated list in `database/gems.yml` for limits only a README states (`protected_attributes_continued`, `paperclip`, `webpacker`, `therubyracer`), each with its source and a count of the files that use it
- Deprecation scan, grouped by pattern, with app vs test occurrence counts; a blocker when this upgrade removes the API; commented-out code is skipped; each links to its Rails guide
- Stops with a clear message when the directory isn't a Rails app
- Config checks: `config.load_defaults` missing or behind the current Rails version
- Docker checks: EOL base image, locale, tzdata, Alpine build deps, Alpine/OpenSSL 3 mismatch
- Database schema checks: charset and integer IDs, applied by target version
- Terminal summary: counts plus each blocker, for SSH sessions and CI logs
- README and report footer point to related tools: next_rails / RailsBump, Brakeman, rubocop-rails
- Single-file HTML report: blockers, items to fix and what couldn't be checked, each linked to its finding; a suggested path; per-section confidence explained in the legend
- Upgrade path with one step per Rails minor version, the Ruby range each needs, and the removed APIs to fix at each step
- "Already broken": APIs removed before the current Rails, and gems past their last supported Rails, listed first in the summary, the terminal and "Before you start"
- Stale gems (online): public gems that depend on Rails and have had no release since before the target Rails shipped, grouped under "couldn't check"; the same rubygems.org lookup as private gem placement, skipped with `--offline`
- Test suite runs with `bundle exec rake`, in GitHub Actions CI on Ruby 2.7 to 4.0
- Deprecation scan covers `app/`, `config/`, `db/`, `lib/`, `test/` and `spec/`, across `.rb`, `.erb` and `.rake`; rules can scope themselves to certain directories with `paths:`. Rules for removed rake tasks also scan `bin/`, `script/`, CI config, Procfiles, Makefiles, Dockerfiles and shell scripts
- 115 deprecation rules, at least one removal per Rails hop from 5.1 to 8.1, each cited to the official release notes
- Every deprecation rule has a sample line in the test suite, and the replacement APIs are checked not to trigger it

## Now

Nothing in progress. Pick the next item from below.

## First public release

The bar is a report that holds up on real apps, not an empty roadmap. In order:

1. **Run it on real apps.** Check out old tagged versions of open-source Rails apps (Discourse, Mastodon, Redmine, …), run the report and review every finding. Every rule is tested only against hand-written sample lines, and false positives are what lose trust fastest. The results will likely reorder the rest of this list.
   - 2026-10-03, two private apps: a Rails 5.2 app (1,923 files; 7 blockers, all real) and a Rails 8.1 app (no findings, even when scanned as if upgrading from 5.0). Found one false positive (hash-rocket keyword args in controller tests) and a bogus upgrade step when already on the target; both fixed in #14.
   - 2026-10-05, same 5.2 app: its Bundler 1.17 lockfile mixes rubygems.org and a private registry in one section. The rubygems.org lookup took minutes and missed 5 of its 11 private gems (private forks under public names); reading the Gemfile's source blocks finds all 11 in about a second (#17).
2. **Grow the gem list** (below). The mechanism is in, with 9 entries, the adapter version table and the sprockets-rails drop; the list covers only what someone has checked.
   - 2026-10-07, the 5.2 app → 7.0: five locked gems cap Rails (responders and active_record_replica below 6.0, acts-as-taggable-on below 6.1, activeresource and acts_as_paranoid below 7.0), and protected_attributes_continued blocks 7.0 across 131 files.
3. **Say when to upgrade Ruby** (below). The upgrade path's main promise is a sequence of steps; repeating "upgrade Ruby first" on every later hop undercuts it.
4. **Make the README accurate.** It claims Rails 3 / 4 support (`compatibility.yml` starts at 5.0) and known public gem incompatibilities (not built yet), and has a `DB/schema.rb` typo.
5. **Release basics.** A CHANGELOG, gemspec metadata, a check that `rails_preflight` is free on rubygems.org, and a 0.x version.

Not needed for the first release: `structure.sql` and anything under Maybe.

## Next: cover more of the upgrade

- **Say when to upgrade Ruby** in the upgrade path: name the step whose Rails supports both the current and the required Ruby. Two symptoms today: every hop's Ruby note compares against the app's *starting* Ruby, and the end-of-life advice ignores the target. For a Rails 5.2 app on Ruby 2.5.9 targeting 6.0, the report says "Upgrade to Ruby 3.3+" while Rails 6.0 supports only up to 2.7. Cap the advice at the target's max Ruby, and point to the later hop where a supported Ruby becomes possible.
- **Deepen the deprecation rules.** Every hop has at least one rule, but the guides list dozens of removals per version. Add the ones that are statically detectable and plausible in app code, applying only those whose `removed_in` falls within the jump. Link each rule to the Rails guides, API docs or a commit, not blog posts, which rot.
- **Grow the gem list** in `database/gems.yml`, citing a README, deprecation notice or Rails source for each entry. The release notes 5.1 → 8.1 have been read in full (2026-10-07); they named few gems, so new entries now come from real-app runs and the stale-gem warning.
- **Support `structure.sql`** in the database checks, not only `db/schema.rb`.
- **Check each gem's declared Rails support** on rubygems.org (skipped with `--offline`): read the Rails dependency its released versions declare, and report "devise 4.7 caps Rails below 6.1; 4.9 allows 7.2, bump it first". Never query gems from a non-rubygems.org source. Overlaps next_rails' `bundle_report compatibility`; the value is one report. Missing upper bounds read as compatible, so the curated list above still matters.
- **Parse the Gemfile with Ripper** instead of line by line, if real Gemfiles hit what the line reader misses: one-line `do … end` and `{ … }` source blocks (these fall back to the rubygems.org lookup) and `x = if … end` inside a source block (closes it early, so its later gems count as public).

## Later

- **`rails-ujs` after 8.1.** The 7.2 notes list "Remove deprecated @rails/ujs", but that was the JS source and build tooling (rails/rails#50535): `rails-ujs.js` still ships in actionview through `8-1-stable`, so `//= require rails-ujs` works. It is gone on `main`; when that Rails ships, add a rule, which needs `.js` scanning under `app/assets` and `app/javascript`.
- Report styling: a design pass over the HTML report, which is mostly inline `style` attributes today
- Print stylesheet, so the report prints or saves to PDF cleanly; an `@media print` block inside the report, since it's a single self-contained file
- JSON output with a stable schema, so CI can gate on it
- Scope flags such as `--exclude-tests`
- Cross-check Ruby version sources (`.ruby-version` vs Dockerfile vs CI config)

## Maybe (to discuss)

- **Changelog database.** Build a database of Rails changelog entries and show the ones relevant to the app in the report. Open question: how much of this the deprecation rules already cover.
- **Upgrade diagram.** A roadmap.sh-style diagram of the actual steps for each upgrade, including when to run `app:update`, etc.
- **More report formats.** JSON (also under Later), Markdown, and maybe a format best suited for other AI tools or MCP servers to ingest.
- **Migration risk in the report.** Some findings can only be fixed with a migration that rewrites a table: integer IDs → bigint, utf8mb3 → utf8mb4. Flag the risk that fix carries next to the finding: table rewrite and locking, uniqueness races when adding unique indexes, a suggested rollout order, and Rails/Postgres/MySQL version caveats. Optionally do the same for migrations in `db/migrate` newer than the schema version. Still read-only: the report flags the risk, it doesn't write or run migrations. Open question: whether it belongs in the first release.

## Not doing

- Automatic fixes, migrations, or code rewriting
- Running the app or its test suite
- One-click upgrades
