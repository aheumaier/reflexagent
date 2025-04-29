module Adapters
  module Notifications
    class SlackNotifier
      include Ports::NotificationPort

      def send_alert(alert)
        # Implementation of NotificationPort#send_alert
        # Will send to Slack in a real implementation
        true
      end

      def send_message(channel, message)
        # Implementation of NotificationPort#send_message
        # Will send to Slack in a real implementation
        true
      end
    end
  end
end
