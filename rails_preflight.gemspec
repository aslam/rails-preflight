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
    .ruby-version, Dockerfile, db/schema.rb and config, and scans Ruby and ERB files for
    deprecated APIs, then writes a single HTML report: blockers, items to fix, what it
    couldn't check, and a suggested path with one step per Rails minor version. Read-only
    and static. It never modifies the app, runs it, or runs its tests.
  DESC
  spec.homepage = "https://github.com/aslam/rails-preflight"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/aslam/rails-preflight"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:test|spec|features)/})
    end
  end

  # For now, manually include everything if git isn't set up
  if spec.files.empty?
    spec.files = Dir["lib/**/*", "bin/*", "database/**/*", "README.md", "Gemfile", "Gemfile.lock", "Dockerfile"]
  end

  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "bundler"
end
