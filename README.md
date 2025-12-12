# Rails Upgrade Audit 🛡️

**Don't guess your upgrade timeline. Audit it.**

A static analysis tool for Rails developers. It scans your legacy project's `Gemfile.lock`, `.ruby-version`, and `Dockerfile` to identify blockers, private dependencies, and infrastructure risks _before_ you write a single line of code.

## Why use this?

Upgrading Rails is hard. Estimating the upgrade is harder.

- **Ruby Version Traps:** Warning you if your target Rails version is incompatible with your current Ruby version (e.g., Rails 5.2 on Ruby 3.4).
- **Private Gems:** Automatically detecting internal gems that need manual review.
- **Docker Timebombs:** Catching OS-level issues like missing `tini` (zombie processes) or Alpine/OpenSSL conflicts.

## Installation

This tool is designed to be run as a standalone script or cloned into your toolbox.

```bash
git clone [https://github.com/yourusername/rails-upgrade-audit.git](https://github.com/yourusername/rails-upgrade-audit.git)
cd rails-upgrade-audit
chmod +x bin/audit
```

Next Steps:

- Deprecation Audit: Scanning code for deprecated Rails methods.
- Configuration Check: verifying config/application.rb.
- Detailed Gem Compatibility: checking gem versions against a matrix.
