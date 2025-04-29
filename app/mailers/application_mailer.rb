class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('MAILER_FROM', 'notifications@example.com')
  layout "mailer"

  def alert_notification(severity:, message:, timestamp:, details: nil)
    @severity = severity
    @message = message
    @timestamp = timestamp
    @details = details

    mail(
      to: notification_recipients,
      subject: "[#{severity.upcase}] Alert: #{message}"
    )
  end

  def general_notification(channel:, message:)
    @channel = channel
    @message = message
    @timestamp = Time.current

    mail(
      to: channel_recipients(channel),
      subject: "[#{channel.upcase}] Notification"
    )
  end

  private

  def notification_recipients
    # This could be replaced with more sophisticated logic based on alert severity,
    # on-call schedules, or user preferences stored in a database
    ENV.fetch('ALERT_RECIPIENTS', 'admin@example.com')
  end

  def channel_recipients(channel)
    # This could be replaced with logic to lookup channel subscribers
    # from a database or configuration
    ENV.fetch('CHANNEL_RECIPIENTS', 'admin@example.com')
  end
end
