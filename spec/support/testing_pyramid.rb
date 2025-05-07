# frozen_string_literal: true

# Configure RSpec to use the testing pyramid
RSpec.configure do |config|
  # Auto-tag specs based on their location
  config.define_derived_metadata(file_path: %r{/spec/unit/}) do |metadata|
    metadata[:level] = :unit
  end

  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:level] = :integration
  end

  config.define_derived_metadata(file_path: %r{/spec/e2e/}) do |metadata|
    metadata[:level] = :e2e
  end

  # Allow filtering by test level
  if ENV["TEST_LEVEL"]
    level = ENV["TEST_LEVEL"].to_sym
    config.filter_run_when_matching level: level
  end

  # Skip problematic tests if the environment variable is set
  if ENV["SKIP_PROBLEMATIC"]
    # Skip request specs that are having issues with controller instantiation
    config.filter_run_excluding problematic: true
  end
end
