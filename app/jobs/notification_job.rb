class NotificationJob < ApplicationJob
  queue_as :notifications

  def perform(alert_id)
    # Send notification for an alert
    send_notification_use_case = UseCaseFactory.create_send_notification
    send_notification_use_case.call(alert_id)
  rescue => e
    Rails.logger.error("Error in NotificationJob for alert #{alert_id}: #{e.message}")
    # Consider retrying or reporting the error to monitoring system
  end
end
