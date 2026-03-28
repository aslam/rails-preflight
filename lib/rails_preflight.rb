require "rails_preflight/version"
require "rails_preflight/upgrade_analyzer"
require "rails_preflight/docker_analyzer"
require "rails_preflight/deprecation_analyzer"
require "rails_preflight/config_analyzer"
require "rails_preflight/database_analyzer"
require "rails_preflight/report_generator"

module RailsPreflight
  class Error < StandardError; end
end
