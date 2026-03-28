# frozen_string_literal: true

require_relative "lib/rails_preflight/version"

Gem::Specification.new do |spec|
  spec.name = "rails_preflight"
  spec.version = RailsPreflight::VERSION
  spec.authors = ["Syed Aslam"]
  spec.email = ["aslam.maqsood@gmail.com"]

  spec.summary = "Pre-upgrade audit and readiness checks for Rails applications."
  spec.description = "Checks Ruby version compatibility, private gems, and Dockerfile best practices before Rails upgrades."
  spec.homepage = "https://github.com/aslam/rails-preflight"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.5.0"

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
