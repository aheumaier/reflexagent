# frozen_string_literal: true

class MetricCalculationJob
  include Sidekiq::Job

  # Set queue name and retry options
  sidekiq_options queue: "metric_calculation", retry: 3

  # Process metric calculations for an event
  # @param event_id [String] The ID of the event to process
  def perform(event_id)
    # Quick UUID format check - just a job-level optimization
    if uuid_format?(event_id.to_s) && !valid_event_id?(event_id)
      Rails.logger.error("Skipping job for non-existent UUID: #{event_id}")
      return
    end

    # Process event through the calculation use case
    metric = process_event(event_id)
    return unless metric

    # Add delay to ensure data consistency across database nodes
    ensure_data_consistency
  rescue StandardError => e
    # Only log and re-raise to maintain Sidekiq retry behavior
    Rails.logger.error("Error in MetricCalculationJob: #{e.message}")
    raise
  end

  private

  def process_event(event_id)
    UseCaseFactory.create_calculate_metrics.call(event_id)
  rescue NoMethodError => e
    # This should only happen if the event doesn't exist, which
    # should be handled by the use case itself
    Rails.logger.error("Calculate Metrics  failed: #{e.message}")
    nil
  end

  def ensure_data_consistency
    # Simple delay to allow database consistency
    sleep(0.5)
  end

  def process_anomaly_detection(metric)
    # The use case should handle all validations internally
    UseCaseFactory.create_detect_anomalies.call(metric.id)
  rescue StandardError => e
    # Don't fail the job if anomaly detection fails
    Rails.logger.error("Anomaly detection failed: #{e.message}")
    nil
  end

  # Utility methods

  def uuid_format?(str)
    uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    uuid_regex.match?(str)
  end

  def valid_event_id?(event_id)
    # Check event existence directly using the event repository
    DependencyContainer.resolve(:event_repository).find_event(event_id).present?
  end
end
