# RailsPreFlight 🛡️

**Assess Rails upgrade risk before you touch a single line of code.**

`rails-preflight` is a static analysis tool that scans legacy Rails applications and produces a **human-readable upgrade risk report**.

It helps teams understand:

- what will block a Rails upgrade
- what is easy vs painful to fix
- where hidden dependency and infrastructure risks exist

This tool is designed for **planning and estimation**, not automated migration.

## Why this exists

Rails upgrades fail not because teams can’t write code, but because they underestimate risk:

- private gems with unknown compatibility
- subtle framework deprecations
- Ruby and OS lifecycle mismatches
- Docker runtime issues that surface late

`rails-preflight` makes these risks visible before you start upgrading.

Think of it as **upgrade reconnaissance**, not a fixer.

## What this tool does

The audit analyzes your project for common Rails upgrade risk factors:

- Ruby & Rails compatibility
- End-of-life Ruby versions
- Private / internal gem dependencies
- Rails deprecations that block upgrades
- Docker runtime risks (EOL base image, locale, tzdata, OpenSSL mismatch)
- Missing Rails configuration required for newer versions

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

## Who this is for

This tool is especially useful if you are:

- Upgrading a Rails 3 / 4 / 5 application
- Planning a security-driven upgrade
- Estimating upgrade effort before committing resources
- Auditing multiple legacy Rails apps
- A consultant or staff engineer responsible for upgrade strategy

## Installation

### Option A: Add to your project (Recommended)

Add this line to your application's `Gemfile`:

```ruby
gem 'rails_preflight', require: false
```

Then run:

```bash
bundle install
bundle exec rails-preflight 6.1
```

### Option B: Standalone

This tool is designed to be run as a standalone script or cloned into your toolbox.

```bash
gem install rails_preflight
```

Then run:

```bash
rails-preflight 6.1 /path/to/your/app
```

The tool will analyze:

- `Gemfile.lock`
- `.ruby-version`
- `Dockerfile` (if present)
- `DB/schema.rb` (if present)
- Application source code (static scan)

And generate:

```
rails_preflight_report.html
```

## Report Overview

The tool generates a self-contained **HTML report** (`rails_preflight_report.html`) that provides a comprehensive view of your upgrade readiness.

### Key Sections

1.  **Executive Summary**: A high-level dashboard showing:
    *   **Risk Score**: A quantitative measure (0-40) of upgrade difficulty.
    *   **Estimated Effort**: T-shirt sizing (Small, Medium, Large) for the upgrade.
    *   **Primary Blockers**: The most critical issues stopping you from upgrading immediately.

2.  **Suggested Upgrade Path**: A generated step-by-step guide tailored to your specific findings, helping you sequence the upgrade work.

3.  **Detailed Findings**:
    *   **Deprecations**: Grouped by message to reduce noise. Expandable to show individual file/line occurrences.
    *   **Gem Compatibility**: Identifies private gems and known public gem incompatibilities.
    *   **Configuration & Infrastructure**: Checks for Docker/OS issues and missing Rails config.
    *   **Database Schema**: Highlights potential data issues (e.g. integer overflows).

4.  **Confidence Badges**: Each section is marked with a confidence level (High/Medium/Low) based on the certainty of the analysis.

## Roadmap

For a detailed list of current features and future plans, please see [ROADMAP.md](ROADMAP.md).

## Philosophy

This tool favors:

- clarity over completeness
- honesty over false confidence
- planning support over automation

If it helps you avoid one failed upgrade attempt, it has done its job.

## License

MIT
