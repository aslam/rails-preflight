# lib/rails_upgrade_audit/docker_analyzer.rb
module RailsUpgradeAudit
  class DockerAnalyzer
    def initialize(dockerfile_path = "Dockerfile")
      @dockerfile_path = dockerfile_path
    end

    def run
      puts "\n[3/3] Scanning Dockerfile..."

      unless File.exist?(@dockerfile_path)
        puts "⚠️  No Dockerfile found at #{@dockerfile_path}. Skipping."
        return
      end

      content = File.read(@dockerfile_path)
      warnings = []

      # RULE 1: Alpine + Nokogiri/PG Trap
      if content.match?(/alpine/)
        unless content.match?(/build-base|libxml2-dev|postgresql-dev/)
          warnings << "🔴 ALPINE RISK: Found 'alpine' base image." \
                      "\n   Ensure 'apk add build-base libxml2-dev' is present for native extensions."
        end

        # RULE 2: Timezone Trap (Alpine doesn't have tzdata by default)
        unless content.match?(/tzdata/)
          warnings << "⚠️  TIMEZONE RISK: Alpine images miss 'tzdata'. Rails Time.zone will fail."
        end
      end

      # RULE 3: Node/Yarn Version Trap for Webpacker
      if content.match?(/NODE_VERSION\s*=\s*['"]?1[0-2]/)
        warnings << "⚠️  NODE JS: Detected Node 10/12. Rails 6+ (Webpacker) usually requires Node 14+."
      end

      # RULE 4: PID 1 Zombie Problem
      unless content.match?(/tini|dumb-init/)
        warnings << "⚠️  ZOMBIE PROCESSES: No init process (tini/dumb-init) detected." \
                    "\n   Rails cannot handle signals properly as PID 1."
      end

      if warnings.any?
        puts "\n🐳 DOCKER WARNINGS FOUND:"
        warnings.each { |w| puts w }
      else
        puts "✅ Dockerfile looks clean (Standard checks passed)."
      end
    end
  end
end
