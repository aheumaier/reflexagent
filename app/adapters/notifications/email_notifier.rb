module Adapters
  module Notifications
    class EmailNotifier
      include Ports::NotificationPort

      def initialize(mailer: ApplicationMailer)
        @mailer = mailer
      end

      def send_alert(alert)
        @mailer.alert_notification(
          severity: alert.severity,
          message: alert.message,
          timestamp: alert.created_at,
          details: alert.details
        ).deliver_now
      end

      def send_message(channel, message)
        @mailer.general_notification(
          channel: channel,
          message: message
        ).deliver_now
      end
    end
  end
end
