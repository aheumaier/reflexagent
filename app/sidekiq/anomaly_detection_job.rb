# frozen_string_literal: true

class AnomalyDetectionJob
  include Sidekiq::Job

  # Set queue name and retry options
  sidekiq_options queue: "anomaly_detection", retry: 3

  # Process anomaly detection for a metric
  # @param metric_id [String] The ID of the metric to analyze
  def perform(metric_id)
    alert = UseCaseFactory.create_detect_anomalies.call(metric_id)
    log_result(metric_id, alert)
  rescue StandardError => e
    Rails.logger.error("Error in AnomalyDetectionJob: #{e.message}")
    raise
  end

  private

  def log_result(metric_id, alert)
    if alert
      Rails.logger.info("Alert created from metric #{metric_id}: #{alert.name}")
    else
      Rails.logger.info("No anomalies detected for metric #{metric_id}")
    end
  end
end
