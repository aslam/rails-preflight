# Rails Upgrade Audit 🛡️

**Don't guess your upgrade timeline. Audit it.**

A static analysis tool for Rails developers. It scans your legacy project's `Gemfile.lock`, `.ruby-version`, and `Dockerfile` to identify blockers, private dependencies, and infrastructure risks _before_ you write a single line of code.

## Why use this?

Upgrading Rails is hard. Estimating the upgrade is harder.

- **Ruby Version Traps:** Warning you if your target Rails version is incompatible with your current Ruby version (e.g., Rails 5.2 on Ruby 3.4).
- **Private Gems:** Automatically detecting internal gems that need manual review.
- **Docker Timebombs:** Catching OS-level issues like missing `tini` (zombie processes) or Alpine/OpenSSL conflicts.

## Installation

### Option A: Add to your project (Recommended)

Add this line to your application's `Gemfile` (usually in the `development` group):

```ruby
group :development do
  gem 'rails_upgrade_audit', git: 'https://github.com/aslam/rails-upgrade-audit.git'
end
```

Then run:

```bash
bundle install
bundle exec rails-upgrade-audit 6.1
```

### Option B: Standalone

This tool is designed to be run as a standalone script or cloned into your toolbox.

```bash
git clone https://github.com/aslam/rails-upgrade-audit.git
cd rails-upgrade-audit
bin/rails-upgrade-audit 6.1 /path/to/your/app
```

## Features:
 
 - **HTML Report Generation:** Generates a self-contained `upgrade_audit.html` report to share with stakeholders. 📊
 - **Database Schema Analysis:** Detects risks like 4-byte integer overflows and legacy MySQL charsets, customized for your target Rails version. 🗄️
 - **Hybrid Code Analysis:** 
    - **Triage:** Fast regex-based scan for major blockers (e.g. `update_attributes`).
    - **Advisory:** Checks for `rubocop-rails` and generates a config to help you deep clean your code. 🤖
 - **Ruby Version Checks:** Ensures compatibility between your lockfile and target Rails version.
 - **Configuration Check:** Verifies critical files like `config/application.rb` for upgrades.
 - **Docker Analysis:** Checks for common Docker pitfalls (Alpine packages, PID 1 issues).
 - **Private Gem Detection:** Highlights internal gems that might block upgrades.
 
 ## Roadmap / Future Ideas:
 
 - **Asset Pipeline Check:** Verifying Node/Yarn versions and precompilation config.
 - **Dynamic Data:** Downloading the latest compatibility databases on the fly.
