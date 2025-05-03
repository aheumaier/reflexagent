# frozen_string_literal: true

# This initializer runs when the Rails application starts
# It ensures we have sample data for testing and demonstration purposes

Rails.application.config.after_initialize do
  # Only run in development environment to prevent production data contamination
  if Rails.env.development?
    Rails.logger.info("Checking for sample data availability")

    # Create sample alerts if none exist
    if defined?(DomainAlert) && DomainAlert.count.zero?
      Rails.logger.info("Creating sample alerts for demonstration")
      DomainAlert.create_sample_alerts(5)
    else
      Rails.logger.info("Sample alerts already exist, skipping creation")
    end

    # If we need sample metrics for testing (could add more seed data here)
    if defined?(DomainMetric) && DomainMetric.count < 10
      Rails.logger.info("Could add sample metrics here if needed")
      # Sample metric creation would go here
    end

    Rails.logger.info("Seeding completed")
  end
end
