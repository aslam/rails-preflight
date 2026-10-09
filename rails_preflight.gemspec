# frozen_string_literal: true

require_relative "lib/rails_preflight/version"

Gem::Specification.new do |spec|
  spec.name = "rails_preflight"
  spec.version = RailsPreflight::VERSION
  spec.authors = ["Syed Aslam"]
  spec.email = ["aslam.maqsood@gmail.com"]

  spec.summary = "Static pre-upgrade audit for Rails apps: what stands between this app and Rails X."
  spec.description = <<~DESC
    Point rails-preflight at a Rails app and a target version. It reads the lockfile,
    .ruby-version, Dockerfile, db/schema.rb and config, and scans Ruby, ERB, HAML and Slim
    files for removed APIs, then writes a single HTML report: blockers, items to fix, what it
    couldn't check, and a suggested path with one step per Rails minor version. The same
    findings print as Markdown for coding agents or JSON for CI. Read-only and static. It
    never modifies the app, runs it, or runs its tests.
  DESC
  spec.homepage = "https://github.com/aslam/rails-preflight"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "bin/*", "database/*.yml", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.bindir = "bin"
  spec.executables = ["rails-preflight"]
  spec.require_paths = ["lib"]
end
