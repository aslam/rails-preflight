# Changelog

## 0.1.0 (unreleased)

First release. Point it at a Rails 5.0 – 8.1 app and a target version; it writes one HTML report and a terminal summary. Read-only and static.

- Upgrade path with one step per Rails minor, the Ruby each step needs, and which step to upgrade Ruby on
- 118 deprecation rules from the release notes, 5.1 to 8.1, scanning code, config YAML and rake tasks in scripts and CI; APIs already removed from the current Rails listed first
- Gem checks: private gems from `Gemfile.lock` and the Gemfile's sources, locked gems whose Rails requirement caps the upgrade, a curated list of gems with known limits, and (online) gems with no release since the target Rails shipped
- Ruby and Node end-of-life, Docker runtime risks, database schema charset and integer IDs, `config.load_defaults`
- `--offline` for a fully static run
- `--format markdown` prints the report as a Markdown checklist for issues, PRs and coding agents
- `--format json` (`"schema": 1`, may change before 1.0) and `--fail-on blockers|broken` to gate CI on the exit code
- Report snippets hide quoted values on lines that name a secret, token or password
