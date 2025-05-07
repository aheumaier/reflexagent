# spec/support/simplecov.rb
require "simplecov"
require "simplecov-console"
require "simplecov_json_formatter"
require "simplecov-lcov"

SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true

# Define formatters for output
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
                                                                  SimpleCov::Formatter::HTMLFormatter,
                                                                  # Removing console formatter to stop showing summary in terminal
                                                                  # SimpleCov::Formatter::Console,
                                                                  SimpleCov::Formatter::LcovFormatter,
                                                                  SimpleCov::Formatter::JSONFormatter
                                                                ])

# Configure SimpleCov
SimpleCov.start "rails" do
  # Enable branch coverage
  enable_coverage :branch

  # Add filters to exclude non-application code
  add_filter "/bin/"
  add_filter "/db/"
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/vendor/"
  add_filter "/lib/tasks/"

  # Organize files into logical groups
  add_group "Core", "app/core"
  add_group "Ports", "app/ports"
  add_group "Adapters", "app/adapters"
  add_group "Controllers", "app/controllers"
  add_group "Models", "app/models"
  add_group "Services", "app/services"
  add_group "Helpers", "app/helpers"
  add_group "Mailers", "app/mailers"
  add_group "Jobs", "app/sidekiq"

  # Minimum coverage percentage (optional, uncomment when ready)
  # minimum_coverage line: 80, branch: 70

  # Track branches, methods, and classes in addition to lines
  track_files "app/**/*.rb"

  # Consider a file as relevant for coverage if it has at least one relevant line
  refuse_coverage_drop
end

# # Show coverage result in console when running tests
# at_exit do
#   SimpleCov.result.format!
# end
