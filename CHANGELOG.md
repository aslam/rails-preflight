# Changelog

## 0.2.0 (2026-10-30)

- Each step links to its RailsDiff and reminds you to run `bin/rails app:update`; JSON steps carry the link as `railsdiff` (#29)
- Dual boot: a tip to set it up when there's none, and a tip to add a CI job when CI doesn't run it (#30)
- A warning when `.ruby-version`, the Dockerfile and CI config disagree on Ruby (#30)
- Secrets committed in config YAML are flagged by file and key, never the value, outside the development and test sections (#31)
- A production `secret_key_base` in `config/secrets.yml` is flagged, as a blocker when the target is Rails 7.2 or later, which stops reading that file; one read from `ENV["SECRET_KEY_BASE"]` isn't (#31)
- The `STATS_DIRECTORIES` message shows its replacement as one code span (#33)

## 0.1.2 (2026-10-13)

- Code inside Packwerk packs (`packs/<name>/app`, `lib`, `spec`, ...) is scanned like the app root, and rules scoped to `app/helpers` or `spec` apply inside packs too (#22, thanks @JuanVqz)
- `BUNDLE_GEMFILE=Gemfile.next rails-preflight` reads that Gemfile and its lockfile, so a dual-boot app can audit its next boot; one outside the app, as `bundle exec` sets it, is ignored (#23, #24, thanks @JuanVqz)
- A compiled binary under `bin/` no longer aborts the run, and scanned files are read as UTF-8 whatever the locale, so a file with non-ASCII characters no longer crashes the scan under `LANG=C` (#21, thanks @JuanVqz)

## 0.1.1 (2026-10-09)

- rubygems.org lookups also trust the certificates RubyGems ships for rubygems.org, so they work wherever `gem install` does, even when Ruby's OpenSSL can't find the system certificates
- Failed lookups are reported once per distinct error, under their own "rubygems.org lookup" entry with the gem names listed once, instead of the same error repeated for every gem under a second "Private Gems" card
- A certificate failure says what to do: behind a VPN or proxy that inspects HTTPS, point `SSL_CERT_FILE` at a bundle that includes its root certificate, or pass `--offline`
- The terminal warns when lookups fail

## 0.1.0 (2026-10-09)

First release. Point it at a Rails 5.0 – 8.1 app and a target version: it writes a report into the app as HTML, Markdown or JSON, plus a short terminal summary. Read-only and static.

- Upgrade path with one step per Rails minor, the Ruby each step needs, and which step to upgrade Ruby on
- 118 deprecation rules from the release notes, 5.0 to 8.1, each cited, scanning `.rb`, `.erb`, `.haml`, `.slim` and `.rake` files, config YAML, and rake tasks in scripts and CI; APIs already removed from the current Rails are listed first as already broken
- Gem checks: private gems from `Gemfile.lock` and the Gemfile's sources; locked gems whose declared Rails requirement caps the upgrade; limits no gemspec declares, which Rails or the gem checks when it loads (database adapters, listen, capybara, selenium-webdriver, redis, google-cloud-storage, bullet); gems the rails gem stops pulling in; a curated list of retired gems; and, online, gems with no release since the target Rails shipped
- Ruby and Node end-of-life, Docker runtime risks, `config.load_defaults`, and schema charset and integer IDs from `db/schema.rb` (an app on `db/structure.sql` gets a note that these were skipped)
- HTML report: verdict, counts, route, plan table, one card per step with files and lines, and what the report can't see; dark mode, print styles, no network requests
- `--format markdown`: a checklist per step for issues, PRs and coding agents
- `--format json`: every finding with its parts (`"schema": 1`, may change before 1.0)
- `--stdout` prints the report instead of writing it, for pipes and coding agents
- `--fail-on blockers|broken` sets the exit code, so CI can gate on it
- `--offline` for a fully static run; private gem names are never sent
- Report snippets hide quoted values on lines that name a secret, token or password
- Checked against real Rails upgrades in Mastodon, Discourse, Forem, Redmine, Coursemology and Fat Free CRM
