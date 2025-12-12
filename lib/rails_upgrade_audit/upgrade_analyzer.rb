# lib/rails_upgrade_audit/upgrade_analyzer.rb
require 'bundler'
require 'net/http'
require 'json'
require 'yaml'
require 'uri'

# Shim for Bundler/Ruby 3.4 compatibility
class Object; def taint; self; end; def untaint; self; end; end
class String; def taint; self; end; def untaint; self; end; end

module RailsUpgradeAudit
  class UpgradeAnalyzer
    DATA_PATH = File.expand_path('../../database/compatibility.yml', __dir__)

    def initialize(target_rails, lockfile_path = "Gemfile.lock")
      @target_rails = target_rails
      @lockfile_path = lockfile_path
      # In a real gem, we might bundle the yaml or load it differently.
      # For now, we assume it's in the gem structure.
      @rules = YAML.load_file(DATA_PATH)
    end

    def run
      puts "🔍 Starting Audit for Rails #{@target_rails}..."
      check_ruby_version
      scan_gems
      DockerAnalyzer.new.run
      DeprecationAnalyzer.new.run
      ConfigAnalyzer.new.run
    end

    private

    def check_ruby_version
      puts "\n[1/2] Checking Ruby Version..."

      # 1. Detect Current Ruby
      if File.exist?(".ruby-version")
        current_raw = File.read(".ruby-version").strip
        source = ".ruby-version"
      else
        current_raw = RUBY_VERSION
        source = "System (RUBY_VERSION)"
      end

      # Clean the version string (handle 'ruby-2.5.9')
      current_str = current_raw.match(/(\d+\.\d+\.\d+)/)[1]
      current_ver = Gem::Version.new(current_str)

      # 2. Check Constraints
      constraints = @rules['rails_versions'][@target_rails]

      unless constraints
        puts "❓ Unknown Rails version: #{@target_rails}"
        return
      end

      min_ver = Gem::Version.new(constraints['required_ruby'].split.last)
      max_ver = Gem::Version.new(constraints['max_ruby'])

      if current_ver < min_ver
        puts "🔴 BLOCKER: Rails #{@target_rails} needs Ruby >= #{min_ver}. You have #{current_ver}."
      elsif current_ver > max_ver
        puts "🔴 BLOCKER: Rails #{@target_rails} is NOT compatible with Ruby #{current_ver}."
        puts "   (Max recommended: #{max_ver}). Expect keyword argument errors!"
      else
        puts "✅ Ruby #{current_ver} (#{source}) is compatible."
      end
    end

    def scan_gems
      puts "\n[2/2] Scanning Gems..."

      # Bypass Bundler IO to avoid version mismatch errors
      content = File.read(@lockfile_path)
      parser = Bundler::LockfileParser.new(content)

      private_gems = []

      parser.specs.each do |spec|
        next if ['rails', 'rake'].include?(spec.name)

        # Quick "Private Gem" Check
        # Real tool would use threads, simplified here for MVP
        if is_private?(spec.name)
          private_gems << spec.name
          print "🔒"
        else
          print "."
        end
      end

      puts "\n\n" + "="*40
      puts "🔒 PRIVATE GEMS DETECTED:"
      puts private_gems.any? ? private_gems : "None"
      puts "="*40
    end

    def is_private?(gem_name)
      url = URI("https://rubygems.org/api/v1/gems/#{gem_name}.json")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE # Fix for your local SSL issue

      response = http.request(Net::HTTP::Get.new(url))
      response.code == '404'
    rescue
      false
    end
  end
end
