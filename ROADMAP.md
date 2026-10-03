# Roadmap

_Last updated: 2026-10-02_

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
- Single-file HTML report: blockers, items to fix and what couldn't be checked, each linked to its finding; a suggested path; per-section confidence explained in the legend
- Upgrade path with one step per Rails minor version, the Ruby range each needs, and the removed APIs to fix at each step
- Test suite runs with `bundle exec rake`, in GitHub Actions CI on Ruby 2.7 to 4.0
- Deprecation scan covers `app/`, `config/`, `db/`, `lib/`, `test/` and `spec/`, across `.rb`, `.erb` and `.rake`; rules can scope themselves to certain directories with `paths:`
- 32 deprecation rules, at least one removal per Rails hop from 5.1 to 8.1, each cited to the official release notes
- Every deprecation rule has a sample line in the test suite, and the replacement APIs are checked not to trigger it

## Now

Nothing in progress. Pick the next item from below.

## Next: cover more of the upgrade

- **Say when to upgrade Ruby** in the upgrade path: name the step whose Rails supports both the current and the required Ruby.
- **Deepen the deprecation rules.** Every hop has at least one rule, but the guides list dozens of removals per version. Add the ones that are statically detectable and plausible in app code, applying only those whose `removed_in` falls within the jump. Link each rule to the Rails guides, API docs or a commit, not blog posts, which rot.
- **Known-incompatible gems.** A curated list of public gems that break or are superseded across a jump (`paperclip`, `protected_attributes`, `therubyracer`, `webpacker`, …), with replacements. Each entry records its source and the Rails versions it applies to, so stale entries expire instead of lingering.
- **Support `structure.sql`** in the database checks, not only `db/schema.rb`.
- **Go offline for gem checks.** Replace the rubygems.org lookup with lockfile-only heuristics, or put it behind an `--online` flag.
- **Point to related tools** in the report and README: `next_rails` / RailsBump for gem compatibility, `brakeman` for security, `rubocop-rails` for autofixes.

## Later

- JSON output with a stable schema, so CI can gate on it
- Scope flags such as `--exclude-tests`
- Cross-check Ruby version sources (`.ruby-version` vs Dockerfile vs CI config)

## Maybe (to discuss)

- **Changelog database.** Build a database of Rails changelog entries and show the ones relevant to the app in the report. Open question: how much of this the deprecation rules already cover.
- **Upgrade diagram.** A roadmap.sh-style diagram of the actual steps for each upgrade, including when to run `app:update`, etc.
- **More report formats.** JSON (also under Later), Markdown, and maybe a format best suited for other AI tools or MCP servers to ingest.

## Not doing

- Automatic fixes, migrations, or code rewriting
- Running the app or its test suite
- One-click upgrades
