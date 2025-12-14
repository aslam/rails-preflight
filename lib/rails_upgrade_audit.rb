require "rails_upgrade_audit/version"
require "rails_upgrade_audit/upgrade_analyzer"
require "rails_upgrade_audit/docker_analyzer"
require "rails_upgrade_audit/deprecation_analyzer"
require "rails_upgrade_audit/config_analyzer"
require "rails_upgrade_audit/database_analyzer"
require "rails_upgrade_audit/report_generator"

module RailsUpgradeAudit
  class Error < StandardError; end
end
