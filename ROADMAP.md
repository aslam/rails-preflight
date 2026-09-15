# Roadmap

_Last updated: 2026-09-15_

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
- Deprecation scan, grouped by pattern, with app vs test occurrence counts; a blocker when the target Rails removes the API; commented-out code is skipped; each links to its Rails guide
- Stops with a clear message when the directory isn't a Rails app
- Config checks: `config.load_defaults` missing or behind the current Rails version
- Docker checks: EOL base image, locale, tzdata, Alpine build deps, Alpine/OpenSSL 3 mismatch
- Database schema checks: charset and integer IDs (6.0 target only)
- Single-file HTML report: blockers, items to fix and what couldn't be checked, each linked to its finding; a suggested path; per-section confidence explained in the legend

## Now: make the report correct and readable

1. **Make the test suite run anywhere.** Add a Rakefile, minitest as a dev dependency, and CI on GitHub Actions.

## Next: cover more of the upgrade

- **Step-by-step upgrade path.** Rails recommends moving one minor version at a time. Use current → target to list each hop (5.2 → 6.0 → 6.1 → 7.0 → …) and the Ruby version it needs.
- **Grow the deprecation rules.** There are two today. Add rules for each hop from the official upgrade guides, and apply only those whose `removed_in` falls within the jump. Link each rule to the Rails guides, API docs or a commit, not blog posts, which rot.
- **Scan views and `config/`.** Only Ruby files under `app/`, `lib/`, `test/` and `spec/` are scanned today. Many removals live in config and routes (e.g. `Rails.application.secrets`, removed in 7.2) or in templates.
- **Known-incompatible gems.** A curated list of public gems that break or are superseded across a jump (`paperclip`, `protected_attributes`, `therubyracer`, `webpacker`, …), with replacements. Each entry records its source and the Rails versions it applies to, so stale entries expire instead of lingering.
- **Database rules by version range**, not only when the target is exactly 6.0. Support `structure.sql`.
- **Go offline for gem checks.** Replace the rubygems.org lookup with lockfile-only heuristics, or put it behind an `--online` flag.
- **Terminal summary.** Print blockers at the end of the run, for SSH sessions and CI logs.
- **Point to related tools** in the report and README: `next_rails` / RailsBump for gem compatibility, `brakeman` for security, `rubocop-rails` for autofixes.

## Later

- JSON output with a stable schema, so CI can gate on it
- Scope flags such as `--exclude-tests`
- Cross-check Ruby version sources (`.ruby-version` vs Dockerfile vs CI config)

## Not doing

- Automatic fixes, migrations, or code rewriting
- Running the app or its test suite
- One-click upgrades
