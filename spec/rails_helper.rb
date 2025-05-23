# This file is copied to spec/ when you run 'rails generate rspec:install'
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.

# Load SimpleCov at the very top for test coverage
require_relative "support/simplecov"

# Load factory_bot configuration
require_relative "support/factory_bot"

# Load shoulda matchers configuration
require_relative "support/shoulda_matchers"

# Load hexagonal helpers
require_relative "support/hexagonal_helpers"

# Load redis test helpers
require_relative "support/redis_helpers"

# Load shared contexts
Dir[Rails.root.join("spec/support/shared_contexts/**/*.rb")].sort.each { |f| require f }

# Load shared examples
Dir[Rails.root.join("spec/support/shared_examples/**/*.rb")].sort.each { |f| require f }

# Load helpers
Dir[Rails.root.join("spec/support/helpers/**/*.rb")].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Setup dependencies for testing
RSpec.configure do |config|
  config.before(:suite) do
    # Reset the dependency container
    DependencyContainer.reset

    # Register mock repositories for testing
    DependencyContainer.register(
      :event_repository,
      Repositories::EventRepository.new
    )
    DependencyContainer.register(
      :metric_repository,
      Repositories::MetricRepository.new
    )
    DependencyContainer.register(
      :alert_repository,
      Repositories::AlertRepository.new
    )
  end

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [Rails.root.join("spec/fixtures")]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/6-0/rspec-rails
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # Include Redis helpers for testing
  config.include RedisHelpers, type: :integration
  config.include RedisHelpers, type: :adapter

  # Include Rails request helpers for request specs
  config.include Rails.application.routes.url_helpers, type: :request
  config.include ActionDispatch::TestProcess::FixtureFile, type: :request
  config.include ActionDispatch::IntegrationTest::Behavior, type: :request

  # Include API request helpers for all request specs
  config.include_context "api_request_helpers", type: :request

  # Skip Redis-dependent tests if Redis is not available
  config.before(:suite) do
    if RedisHelpers.redis_available?
      puts "\nRedis is available. Running Redis-dependent tests."
    else
      puts "\nRedis is not available. Skipping Redis-dependent tests."
    end
  end

  # Filter examples requiring Redis if it's not available
  config.filter_run_excluding redis: true unless RedisHelpers.redis_available?
end
