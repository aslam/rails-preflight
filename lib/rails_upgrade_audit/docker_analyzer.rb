# lib/rails_upgrade_audit/docker_analyzer.rb
module RailsUpgradeAudit
  class DockerAnalyzer
    def initialize(root_path = Dir.pwd)
      @dockerfile_path = File.join(root_path, "Dockerfile")
    end

    def detect_ruby_version
      return nil unless File.exist?(@dockerfile_path)
      content = File.read(@dockerfile_path)
      if match = content.match(/FROM ruby:(\S+)/)
        match[1]
      end
    end

    def run
      result = { title: "Docker Configuration", status: :passed, checks: [] }
      
      dockerfile = @dockerfile_path # Use @dockerfile_path as defined in initialize

      unless File.exist?(dockerfile)
        result[:status] = :warning
        result[:checks] << { message: "No Dockerfile found at #{dockerfile}. Skipping.", status: :warning }
        return result
      end

      content = File.read(dockerfile)
      
      # Check Ruby version in Dockerfile
      if match = content.match(/FROM ruby:(\S+)/)
        docker_ruby = match[1]
        result[:checks] << { message: "Dockerfile uses Base Image: ruby:#{docker_ruby}", status: :passed }
      else
        result[:checks] << { message: "Could not detect FROM ruby image in Dockerfile.", status: :warning }
        result[:status] = :warning
      end

      # Check for typical pitfalls
      if content.include?("bundle install") && !content.include?("without")
        result[:status] = :warning
        result[:checks] << { message: "Optimization: 'bundle install' should probably use '--without development test'", status: :warning }
      end
      
      # RULE 1: Alpine + Nokogiri/PG Trap
      if content.match?(/alpine/)
        unless content.match?(/build-base|libxml2-dev|postgresql-dev/)
          result[:status] = :warning
          result[:checks] << { message: "ALPINE RISK: Found 'alpine' base image. Ensure 'apk add build-base libxml2-dev' is present for native extensions.", status: :warning }
        end

        # RULE 2: Timezone Trap (Alpine doesn't have tzdata by default)
        unless content.match?(/tzdata/)
          result[:status] = :warning
          result[:checks] << { message: "TIMEZONE RISK: Alpine images miss 'tzdata'. Rails Time.zone will fail.", status: :warning }
        end
      end

      # RULE 3: Node/Yarn Version Trap for Webpacker
      if content.match?(/NODE_VERSION\s*=\s*['"]?1[0-2]/)
        result[:status] = :warning
        result[:checks] << { message: "NODE JS: Detected Node 10/12. Rails 6+ (Webpacker) usually requires Node 14+.", status: :warning }
      end

      # RULE 4: PID 1 Zombie Problem
      unless content.match?(/tini|dumb-init/)
        result[:status] = :warning
        result[:checks] << { message: "ZOMBIE PROCESSES: No init process (tini/dumb-init) detected. Rails cannot handle signals properly as PID 1.", status: :warning }
      end

      if result[:checks].none? { |c| c[:status] != :passed }
         # If we didn't add any specific failures but found the file
         # We implicitly passed.
      end

      result
    end
  end
end
