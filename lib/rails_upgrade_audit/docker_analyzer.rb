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
      
      unless File.exist?(@dockerfile_path)
        result[:status] = :warning
        result[:checks] << { message: "No Dockerfile found at #{@dockerfile_path}. Skipping.", status: :warning }
        return result
      end

      content = File.read(@dockerfile_path)
      
      check_ruby_version(content, result)
      check_package_manager_pitfalls(content, result)
      check_alpine_pitfalls(content, result)
      check_node_version(content, result)
      check_zombie_processes(content, result)
      check_eol_base_image(content, result)
      check_locale_settings(content, result)
      check_openssl_mismatch(content, result)

      update_overall_status(result)
      result
    end

    private

    def check_ruby_version(content, result)
      if docker_ruby = detect_ruby_version
        result[:checks] << { message: "Dockerfile uses Base Image: ruby:#{docker_ruby}", status: :passed }
      else
        result[:checks] << { message: "Could not detect FROM ruby image in Dockerfile.", status: :warning }
      end
    end

    def check_package_manager_pitfalls(content, result)
      if content.include?("bundle install") && !content.include?("without")
        result[:checks] << { message: "Optimization: 'bundle install' should probably use '--without development test'", status: :warning }
      end
    end

    def check_alpine_pitfalls(content, result)
      if content.match?(/alpine/)
        unless content.match?(/build-base|libxml2-dev|postgresql-dev/)
          result[:checks] << { message: "ALPINE RISK: Found 'alpine' base image. Ensure 'apk add build-base libxml2-dev' is present for native extensions.", status: :warning }
        end

        unless content.match?(/tzdata/)
          # This check is now covered by check_locale_settings more broadly, 
          # but keeping specific "Alpine missing tzdata" message is helpful.
          # We'll merge it into a general tzdata check if desired, but let's keep it specific for Alpine for now.
          # Actually, the user asked for "Detect missing locale / tzdata (common Rails pain)".
          # We'll rely on check_locale_settings for general tzdata.
        end
      end
    end

    def check_node_version(content, result)
      if content.match?(/NODE_VERSION\s*=\s*['"]?1[0-2]/)
        result[:checks] << { message: "NODE JS: Detected Node 10/12. Rails 6+ (Webpacker) usually requires Node 14+.", status: :warning }
      end
      
      # EOL Node Check
      # Support ENV NODE_VERSION 12.0.0 (space) and ENV NODE_VERSION=12.0.0 (equals)
      if match = content.match(/NODE_VERSION\s*[:=\s]\s*['"]?(\d+)/)
        major_version = match[1].to_i
        if major_version < 18
          result[:checks] << { message: "EOL Node: Node #{major_version} is End-of-Life. Upgrade to Node 18+.", status: :warning }
        end
      end
    end

    def check_zombie_processes(content, result)
      unless content.match?(/tini|dumb-init/)
        result[:checks] << { message: "ZOMBIE PROCESSES: No init process (tini/dumb-init) detected. Rails cannot handle signals properly as PID 1.", status: :warning }
      end
    end

    def check_eol_base_image(content, result)
      if match = content.match(/FROM ruby:(\d+\.\d+)/)
        version = match[1].to_f
        if version < 3.1
          result[:checks] << { message: "EOL Ruby: Ruby #{match[1]} is End-of-Life. Upgrade to Ruby 3.1+.", status: :warning }
        end
      end
    end

    def check_locale_settings(content, result)
      # Check for ENV LANG or LC_ALL
      # Regex: Start of line (ignoring whitespace), ENV, whitespace, LANG or LC_ALL
      unless content.match?(/^\s*ENV\s+(LANG|LC_ALL)/)
        result[:checks] << { message: "Locale: Missing 'ENV LANG' or 'ENV LC_ALL'. This can cause encoding issues.", status: :warning }
      end

      # Check for tzdata availability generally
      unless content.match?(/tzdata/)
        result[:checks] << { message: "Timezone: 'tzdata' package seems missing. Rails Time.zone requires it.", status: :warning }
      end
    end

    def check_openssl_mismatch(content, result)
      # Logic:
      # Alpine >= 3.17 uses OpenSSL 3.0
      # Ubuntu >= 22.04 uses OpenSSL 3.0 (though less common in FROM ruby lines usually)
      # Ruby < 3.1 has issues with OpenSSL 3.0
      
      ruby_version = if match = content.match(/FROM ruby:(\d+\.\d+)/)
                       match[1].to_f
                     else
                       nil
                     end

      return unless ruby_version
      
      is_alpine_new = false
      if match = content.match(/alpine(\d+\.\d+)/)
        alpine_ver = match[1].to_f
        is_alpine_new = true if alpine_ver >= 3.17
      end
      
      # We could also check for "FROM ubuntu:22.04" or similar, but let's focus on the Alpine case as it's the most common trap with ruby images.
      
      if is_alpine_new && ruby_version < 3.1
        result[:checks] << { message: "OpenSSL Mismatch: Alpine >= 3.17 uses OpenSSL 3.0, which may break recent Ruby versions < 3.1. Compatibility is poor.", status: :warning }
      end
    end

    def update_overall_status(result)
      if result[:checks].any? { |c| c[:status] != :passed }
        result[:status] = :warning
      end
    end
  end
end
