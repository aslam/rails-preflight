# Changelog

## 0.1.0 (unreleased)

First release. Point it at a Rails 5.0 – 8.1 app and a target version: it writes an HTML report, or prints it as Markdown or JSON, plus a short terminal summary. Read-only and static.

- Upgrade path with one step per Rails minor, the Ruby each step needs, and which step to upgrade Ruby on
- 118 deprecation rules from the release notes, 5.0 to 8.1, each cited, scanning `.rb`, `.erb`, `.haml`, `.slim` and `.rake` files, config YAML, and rake tasks in scripts and CI; APIs already removed from the current Rails are listed first as already broken
- Gem checks: private gems from `Gemfile.lock` and the Gemfile's sources; locked gems whose declared Rails requirement caps the upgrade; limits no gemspec declares, which Rails or the gem checks when it loads (database adapters, listen, capybara, selenium-webdriver, redis, google-cloud-storage, bullet); gems the rails gem stops pulling in; a curated list of retired gems; and, online, gems with no release since the target Rails shipped
- Ruby and Node end-of-life, Docker runtime risks, `config.load_defaults`, and schema charset and integer IDs from `db/schema.rb` (an app on `db/structure.sql` gets a note that these were skipped)
- HTML report: verdict, counts, route, plan table, one card per step with files and lines, and what the report can't see; dark mode, print styles, no network requests
- `--format markdown`: a checklist per step for issues, PRs and coding agents
- `--format json`: every finding with its parts (`"schema": 1`, may change before 1.0)
- `--fail-on blockers|broken` sets the exit code, so CI can gate on it
- `--offline` for a fully static run; private gem names are never sent
- Report snippets hide quoted values on lines that name a secret, token or password
- Checked against real Rails upgrades in Mastodon, Discourse, Forem, Redmine, Coursemology and Fat Free CRM
