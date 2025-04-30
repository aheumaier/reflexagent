class MetricCalculationJob < ApplicationJob
  queue_as :metrics

  def perform(event_id)
    # Create the use cases through the factory
    calculate_metrics = UseCaseFactory.create_calculate_metrics
    detect_anomalies = UseCaseFactory.create_detect_anomalies

    # Step 1: Calculate metrics from the event
    metric = calculate_metrics.call(event_id)

    # Step 2: Detect anomalies if we got a metric
    if metric
      alert = detect_anomalies.call(metric.id)

      # Log alert creation for debugging
      Rails.logger.info("Alert created: #{alert.name}") if alert
    end
  rescue StandardError => e
    Rails.logger.error("Error in MetricCalculationJob: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end
end
