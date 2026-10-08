# RailsPreFlight 🛡️

**Assess Rails upgrade risk before you touch a single line of code.**

`rails-preflight` is a static analysis tool that scans legacy Rails applications and produces a **human-readable upgrade risk report**.

It helps teams understand:

- what will block a Rails upgrade
- what is easy vs painful to fix
- where hidden dependency and infrastructure risks exist

This tool is designed for **planning and scoping**, not automated migration.

## Why this exists

Rails upgrades fail not because teams can’t write code, but because they underestimate risk:

- private gems with unknown compatibility
- subtle framework deprecations
- Ruby and OS lifecycle mismatches
- Docker runtime issues that surface late

`rails-preflight` makes these risks visible before you start upgrading.

Think of it as **upgrade reconnaissance**, not a fixer. Run it before the upgrade starts, whoever does it: your team, a consultant or a coding agent.

## What this tool does

The audit analyzes your project for common Rails upgrade risk factors:

- Ruby & Rails compatibility, and which upgrade step to move Ruby on
- End-of-life Ruby and Node versions
- Private / internal gem dependencies
- Locked gems whose declared Rails requirement caps the upgrade, plus a curated list of gems with known limits
- Removed and deprecated Rails APIs in code, config YAML, rake tasks in scripts and CI, including ones already removed from your current Rails
- Docker runtime risks (EOL base image, locale, tzdata, OpenSSL mismatch)
- Database schema risks (charset, integer IDs)
- Missing or outdated `config.load_defaults`

The output is a **single HTML report** designed to be:

- readable by engineers
- understandable by EMs and tech leads
- usable in upgrade planning discussions

## What this tool intentionally does NOT do

- ❌ It does not modify your code
- ❌ It does not auto-fix deprecations
- ❌ It does not guarantee upgrade success
- ❌ It is not a replacement for running tests or CI

If you’re looking for a “one-click upgrade,” this is not that tool.

## Related tools

These cover what `rails-preflight` leaves out, and pair well with it:

- [next_rails](https://github.com/fastruby/next_rails) or [RailsBump](https://railsbump.org): which gem versions work with your target Rails
- [Brakeman](https://brakemanscanner.org): security issues
- [rubocop-rails](https://github.com/rubocop/rubocop-rails): autofixes for many deprecations

## Who this is for

This tool is especially useful if you are:

- Upgrading a Rails 5.0 or newer application (Rails 3 and 4 aren't covered)
- Planning a security-driven upgrade
- Scoping an upgrade before committing resources
- Auditing multiple legacy Rails apps
- A consultant or staff engineer responsible for upgrade strategy

## Installation

Install it globally and point it at your app. It only reads files, so the app can be on any Ruby version, including the old one your servers run. The machine running it needs Ruby 2.7 or newer.

```bash
gem install rails_preflight
rails-preflight /path/to/your/app
```

With no target, it reports on the next Rails minor after the app's (5.2 → 6.0, 7.1 → 7.2), the step Rails recommends taking next. Pass a target to plan a bigger jump: `rails-preflight 8.1 /path/to/your/app`. Leave out the path to audit the current directory.

Private gems come from `Gemfile.lock` and the Gemfile's `source` blocks, which are read, never run. Only when neither says where a gem comes from does the tool ask rubygems.org. It also asks rubygems.org when each public gem that depends on Rails last had a release, and lists the ones with nothing newer than the target Rails: nothing says they break, but nobody may have tried. Private gem names are never sent. Pass `--offline` for a fully static run; unplaced gems are then reported as unchecked, and release dates are skipped.

It knows Rails 5.0 to 8.1 (`database/compatibility.yml`); the default target is only as current as that list.

The tool will analyze:

- `Gemfile` and `Gemfile.lock`
- `.ruby-version`
- `Dockerfile` (if present)
- `db/schema.rb` (if present)
- `config/application.rb` and `config/**/*.yml`
- `.rb`, `.erb` and `.rake` files under `app/`, `config/`, `db/`, `lib/`, `test/` and `spec/`
- Scripts and CI config (`bin/`, `script/`, Procfiles, Makefiles, CI workflows) for removed rake tasks

And generate:

```
rails_preflight_report.html
```

## Report Overview

The tool writes one self-contained **HTML report** (`rails_preflight_report.html`). It makes no network requests when opened, follows the OS dark mode, and prints on A4.

1.  **Title and verdict**: `app: Rails current to target`, then one sentence: how many steps, when to upgrade Ruby, how many blockers.

2.  **Counts**, each linked to where the findings are:
    *   **Already broken**: APIs removed before your current Rails, or gems past their last supported Rails. That code fails when it runs, or never runs.
    *   **Blockers**: must be fixed before the upgrade can work (e.g. Ruby too old, removed APIs still in use).
    *   **To fix**: will warn or break along the way (deprecations, lagging config), split into now and later versions.
    *   **Couldn't check**: what the tool could not verify (private gems, missing files), to review by hand.

3.  **Route and plan**: one stop per Rails minor, since Rails recommends upgrading one at a time, with the blockers at each. Later versions past the target are faded and count the code they remove, found in the same scan. A table gives each step's work, the Ruby it needs and a relative effort: the hardest single fix in it (low, medium or high, set per check), not the amount of work. The occurrence counts on each finding show that.

4.  **Steps**: "Before you start" for findings that don't belong to a step, then one card per step with its Ruby range and the removed APIs and gems to fix for it. Each finding links to the Rails release notes or the gem's source; its occurrence line expands to file, line and snippet, with app and test occurrences counted apart.

5.  **Ahead of the target**: code that later Rails versions remove, by version. Not needed now.

6.  **What this report can't see**: private gems and quiet gems by name, behavior changes, multi-line code and test coverage, with what to do instead.

7.  **Footer**: the confidence of each section (read from project files, pattern matches, or a key input missing) and where the findings come from.

## Roadmap

For a detailed list of current features and future plans, please see [ROADMAP.md](ROADMAP.md).

## Philosophy

This tool favors:

- clarity over completeness
- honesty over false confidence
- planning support over automation

If it helps you avoid one failed upgrade attempt, it has done its job.

## Development

```bash
bundle install
bundle exec rake
```

CI runs the suite on every Ruby from 2.7 to 4.0.

## License

MIT
