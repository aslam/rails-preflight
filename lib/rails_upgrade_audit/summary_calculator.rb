module RailsUpgradeAudit
  class SummaryCalculator
    def initialize(results)
      @results = results
    end

    def calculate
      {
        overall_risk: calculate_risk,
        estimated_effort: calculate_effort,
        primary_blockers: identify_blockers,
        upgrade_score: calculate_score
      }
    end

    private

    def calculate_score
      score = 0
      
      # 1. Private Gems (+3 each)
      score += count_private_gems * 3
      
      # 2. Ruby Version (+5 if blocker)
      ruby_check = @results.find { |r| r[:title] == "Ruby Version" }
      if ruby_check && ruby_check[:status] == :failed
        score += 5
      end
      
      # 3. Docker Issues (+2 if warnings/failed)
      docker_check = @results.find { |r| r[:title] == "Docker Analysis" }
      if docker_check && (docker_check[:status] == :warning || docker_check[:status] == :failed)
        score += 2
      end
      
      # 4. Deprecations (+0.2 each, capped at 10)
      deprecations_score = count_deprecations * 0.2
      score += [deprecations_score, 10.0].min
      
      # Return scaled string "X / 40"
      "#{score.round(1)} / 40"
    end

    def calculate_risk
      # Risk Logic:
      # High: Any failed checks (blockers) or > 3 warnings
      # Medium: 1-3 warnings
      # Low: 0 warnings, 0 failures
      if failed_checks_count > 0 || warning_checks_count > 3
        "High"
      elsif warning_checks_count > 0
        "Medium"
      else
        "Low"
      end
    end

    def calculate_effort
      # Effort Logic (Heuristic):
      # Large: > 20 deprecations OR > 5 private gems OR any Ruby version blocker
      # Medium: 5-20 deprecations OR 1-5 private gems
      # Small: < 5 deprecations
      
      deprecation_count = count_deprecations
      private_gem_count = count_private_gems
      ruby_blocker = @results.find { |r| r[:title] == "Ruby Version" && r[:status] == :failed }

      if deprecation_count > 20 || private_gem_count > 5 || ruby_blocker
        "Large"
      elsif deprecation_count > 5 || private_gem_count > 0
        "Medium"
      else
        "Small"
      end
    end

    def identify_blockers
      blockers = []

      # 1. Private Gems
      private_gems_check = find_check("Private Gems", "Private Gems Detected")
      if private_gems_check
        count = private_gems_check[:details].size
        blockers << "#{count} private gems (unknown compatibility)"
      end

      # 2. Ruby Version
      ruby_check = @results.find { |r| r[:title] == "Ruby Version" }
      if ruby_check && ruby_check[:status] == :failed
        # Grab the first failure message
        msg = ruby_check[:checks].find { |c| c[:status] == :failed }[:message]
        blockers << msg
      end

      # 3. Deprecations
      deprecation_count = count_deprecations
      if deprecation_count > 0
        blockers << "#{deprecation_count} Rails deprecations found"
      end

      # 4. Incomplete Analysis
      incomplete_check = @results.flat_map { |r| r[:checks] }.find { |c| c[:message]&.start_with?("Analysis Incomplete") }
      if incomplete_check
        blockers << incomplete_check[:message]
      end

      blockers
    end

    def count_deprecations
      section = @results.find { |r| r[:title] == "Deprecation Warnings" }
      return 0 unless section
      
      # If status is passed, check for "No obvious..." message, count is 0
      # If status is warning, count the checks that are warnings
      return 0 if section[:status] == :passed

      section[:checks].count { |c| c[:status] == :warning && !c[:message].start_with?("💡 Recommendation") }
    end

    def count_private_gems
      check = find_check("Private Gems", "Private Gems Detected")
      return 0 unless check
      check[:details].size
    end

    def find_check(section_title, message_start)
      section = @results.find { |r| r[:title] == section_title }
      return nil unless section
      section[:checks].find { |c| c[:message].start_with?(message_start) }
    end

    def failed_checks_count
      @results.sum { |section| section[:checks].count { |c| c[:status] == :failed } }
    end

    def warning_checks_count
      @results.sum { |section| section[:checks].count { |c| c[:status] == :warning } }
    end
  end
end
