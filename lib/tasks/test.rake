namespace :test do
  desc "Configure the testing pyramid structure"
  task :configure_pyramid do
    # This task is automatically run before any other test:* tasks
    ENV["CONFIGURE_TEST_PYRAMID"] = "true"
  end

  desc "Run unit tests (fast)"
  task unit: :configure_pyramid do
    ENV["PYRAMID_LEVEL"] = "unit"
    Rake::Task["spec"].invoke
  end

  desc "Run integration tests (medium)"
  task integration: :configure_pyramid do
    ENV["PYRAMID_LEVEL"] = "integration"
    Rake::Task["spec"].invoke
  end

  desc "Run end-to-end tests (slow)"
  task e2e: :configure_pyramid do
    ENV["PYRAMID_LEVEL"] = "e2e"
    ENV["RUN_SLOW_TESTS"] = "true"
    Rake::Task["spec"].invoke
  end

  desc "Run all tests in the pyramid order (unit, integration, e2e)"
  task pyramid: [:unit, :integration, :e2e]

  # Override the default Rails test task to use our pyramid
  task default: :pyramid
end

# Ensure our rake tasks are loaded by Rails
Rake::Task.define_task(:environment)
