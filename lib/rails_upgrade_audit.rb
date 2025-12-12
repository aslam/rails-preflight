require "rails_upgrade_audit/version"
require "rails_upgrade_audit/upgrade_analyzer"
require "rails_upgrade_audit/docker_analyzer"
require "rails_upgrade_audit/deprecation_analyzer"
require "rails_upgrade_audit/config_analyzer"

module RailsUpgradeAudit
  class Error < StandardError; end
end
