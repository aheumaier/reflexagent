module UseCases
  class SendNotification
    def initialize(notification_port:, storage_port:)
      @notification_port = notification_port
      @storage_port = storage_port
    end

    def call(alert_id)
      alert = @storage_port.find_alert(alert_id)
      @notification_port.send_alert(alert)
    end
  end
end
