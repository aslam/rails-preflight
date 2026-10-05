# Roadmap

_Last updated: 2026-10-03_

rails-preflight answers one question about a Rails app: **what stands between this app and Rails X, and how sure are we?** Everything below makes that answer more correct, easier to read, or broader.

## Principles

- **Read-only.** Never modifies the app. The only file it writes is the report.
- **Static and offline.** Reads files. Doesn't run the app, its tests, or call the network.
- **Deterministic.** Same app, same report.
- **Honest.** Every number in the report traces back to a finding. When we can't tell, we say so instead of guessing.

## Shipped

- Current Rails version from `Gemfile.lock`, shown as `current → target` in the report and upgrade path
- Ruby compatibility per target Rails (5.0 – 8.1), read from `.ruby-version`, `Gemfile.lock`, or the Dockerfile
- EOL checks for Ruby and Node
- Private gem detection (git/path sources, non-rubygems.org remotes)
- Deprecation scan, grouped by pattern, with app vs test occurrence counts; a blocker when this upgrade removes the API; commented-out code is skipped; each links to its Rails guide
- Stops with a clear message when the directory isn't a Rails app
- Config checks: `config.load_defaults` missing or behind the current Rails version
- Docker checks: EOL base image, locale, tzdata, Alpine build deps, Alpine/OpenSSL 3 mismatch
- Database schema checks: charset and integer IDs, applied by target version
- Terminal summary: counts plus each blocker, for SSH sessions and CI logs
- README and report footer point to related tools: next_rails / RailsBump, Brakeman, rubocop-rails
- Single-file HTML report: blockers, items to fix and what couldn't be checked, each linked to its finding; a suggested path; per-section confidence explained in the legend
- Upgrade path with one step per Rails minor version, the Ruby range each needs, and the removed APIs to fix at each step
- Test suite runs with `bundle exec rake`, in GitHub Actions CI on Ruby 2.7 to 4.0
- Deprecation scan covers `app/`, `config/`, `db/`, `lib/`, `test/` and `spec/`, across `.rb`, `.erb` and `.rake`; rules can scope themselves to certain directories with `paths:`
- 63 deprecation rules, at least one removal per Rails hop from 5.1 to 8.1, each cited to the official release notes
- Every deprecation rule has a sample line in the test suite, and the replacement APIs are checked not to trigger it

## Now

Nothing in progress. Pick the next item from below.

## First public release

The bar is a report that holds up on real apps, not an empty roadmap. In order:

1. **Run it on real apps.** Check out old tagged versions of open-source Rails apps (Discourse, Mastodon, Redmine, …), run the report and review every finding. Every rule is tested only against hand-written sample lines, and false positives are what lose trust fastest. The results will likely reorder the rest of this list.
   - 2026-10-03, two private apps: a Rails 5.2 app (1,923 files; 7 blockers, all real) and a Rails 8.1 app (no findings, even when scanned as if upgrading from 5.0). Found one false positive (hash-rocket keyword args in controller tests) and a bogus upgrade step when already on the target; both fixed in #14.
2. **Default to the next Rails version.** Make the target optional: with no argument, read the current Rails from `Gemfile.lock` and target the next minor in `compatibility.yml` (5.2 → 6.0, 7.1.3 → 7.2, 7.2 → 8.0). Rails recommends one minor at a time, and that's the report a team acts on: the 5.2 app had 2 blockers targeting 6.0 against 7 targeting 8.1. An explicit target keeps working for planning the whole jump, and the default run ends with a one-line hint ("Latest known is 8.1: run `rails-preflight 8.1` for the full path"). With no `Gemfile.lock` or no Rails in it, stop and ask for a target instead of guessing; when already on the newest known version, say so and exit. The default is only as current as `compatibility.yml`, so the README states which Rails versions the tool knows. It changes the CLI, so it goes in before the first release, not after.
3. **Known-incompatible gems** (below). Gems block more upgrades than removed APIs do; without this, the report misses the biggest risk on most apps.
4. **Say when to upgrade Ruby** (below). The upgrade path's main promise is a sequence of steps; repeating "upgrade Ruby first" on every later hop undercuts it.
5. **Make the README accurate.** It claims Rails 3 / 4 support (`compatibility.yml` starts at 5.0) and known public gem incompatibilities (not built yet), and has a `DB/schema.rb` typo.
6. **Go offline for gem checks.** Done: private gems come from the lockfile alone. A `GEM` section that lists rubygems.org next to a private registry (as on the 5.2 app) is reported as "couldn't check" instead of costing one rubygems.org request per gem, which took minutes, drifted run to run on timeouts, and sent private gem names to a public server. Next is the `--online` flag (below).
7. **Release basics.** A CHANGELOG, gemspec metadata, a check that `rails_preflight` is free on rubygems.org, and a 0.x version.

Not needed for the first release: `structure.sql` and anything under Maybe.

## Next: cover more of the upgrade

- **Say when to upgrade Ruby** in the upgrade path: name the step whose Rails supports both the current and the required Ruby. Two symptoms today: every hop's Ruby note compares against the app's *starting* Ruby, and the end-of-life advice ignores the target. For a Rails 5.2 app on Ruby 2.5.9 targeting 6.0, the report says "Upgrade to Ruby 3.3+" while Rails 6.0 supports only up to 2.7. Cap the advice at the target's max Ruby, and point to the later hop where a supported Ruby becomes possible.
- **Flag removals that predate the current Rails.** An API removed before the app's current version is reported as "to fix", but it is either dead code or already broken in production. On the Rails 5.2 app, `render text:` (removed in 5.1) sat in a live `before_action`, so outdated clients likely get a 500 instead of the intended 426. Give these their own label, e.g. "already broken or dead code", and list them first.
- **Deepen the deprecation rules.** Every hop has at least one rule, but the guides list dozens of removals per version. Add the ones that are statically detectable and plausible in app code, applying only those whose `removed_in` falls within the jump. Link each rule to the Rails guides, API docs or a commit, not blog posts, which rot.
- **Known-incompatible gems.** A curated list of public gems that break or are superseded across a jump (`paperclip`, `protected_attributes`, `therubyracer`, `webpacker`, …), with replacements. Each entry records its source and the Rails versions it applies to, so stale entries expire instead of lingering. Each entry also carries an optional code pattern, so the report can say how much code depends on the gem, not just that it's there. Before the target, report it under "to fix" with the deadline ("supports Rails up to 6.1; plan the move before 7.0"); at or past it, make it a blocker on the hop where support ends. First entry: `protected_attributes_continued`, which its README says supports Rails 5.0 – 6.1 only, with a pattern for `attr_accessible` / `attr_protected`. On the Rails 5.2 app from the real-app run that's 139 files, likely the biggest single piece of its upgrade, and the report said nothing about it.
- **Support `structure.sql`** in the database checks, not only `db/schema.rb`.
- **`--online` gem checks.** Opt-in network access: for each gem from rubygems.org, read the Rails dependency its released versions declare, and report "devise 4.7 caps Rails below 6.1; 4.9 allows 7.2, bump it first". Never query gems from a non-rubygems.org source, and say in the report which mode ran. Overlaps next_rails' `bundle_report compatibility`; the value is one report. Missing upper bounds read as compatible, so the curated list below still matters.
- **Rename "known-incompatible gems"** to "Gems with a Rails support ceiling".

## Later

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
