class AnomalyDetectionJob < ApplicationJob
  queue_as :anomalies

  def perform(metric_id)
    # Detect anomalies and create alerts if needed
    detect_anomalies_use_case = UseCaseFactory.create_detect_anomalies
    alert = detect_anomalies_use_case.call(metric_id)

    # If an alert was created, enqueue notification
    if alert
      NotificationJob.perform_async(alert.id)
    end
  rescue => e
    Rails.logger.error("Error in AnomalyDetectionJob for metric #{metric_id}: #{e.message}")
    # Consider retrying or reporting the error to monitoring system
  end
end
