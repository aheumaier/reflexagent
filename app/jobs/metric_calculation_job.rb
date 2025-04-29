class MetricCalculationJob < ApplicationJob
  queue_as :metrics

  def perform(event_id)
    # Calculate metrics from the event
    calculate_metrics_use_case = UseCaseFactory.create_calculate_metrics
    metric = calculate_metrics_use_case.call(event_id)

    # Check for anomalies
    if metric
      AnomalyDetectionJob.perform_async(metric.id)
    end
  rescue => e
    Rails.logger.error("Error in MetricCalculationJob for event #{event_id}: #{e.message}")
    # Consider retrying or reporting the error to monitoring system
  end
end
