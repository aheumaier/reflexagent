require "rails_helper"

RSpec.describe Notifications::EmailNotifier do
  let(:mailer) { instance_double(ApplicationMailer) }
  let(:notifier) { described_class.new(mailer: mailer) }
  let(:mail_message) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }

  let(:metric) do
    Domain::Metric.new(
      name: "cpu.usage",
      value: 85.5,
      source: "web-01",
      dimensions: { region: "us-west", environment: "production" }
    )
  end

  let(:alert) do
    Domain::Alert.new(
      name: "High CPU Usage",
      severity: :warning,
      metric: metric,
      threshold: 80.0
    )
  end

  describe "#send_alert" do
    it "sends alert email through the mailer" do
      allow(mailer).to receive(:alert_notification).with(
        severity: alert.severity,
        message: alert.message,
        timestamp: alert.created_at,
        details: alert.details
      ).and_return(mail_message)

      notifier.send_alert(alert)

      expect(mailer).to have_received(:alert_notification)
      expect(mail_message).to have_received(:deliver_now)
    end
  end

  describe "#send_message" do
    it "sends general notification email through the mailer" do
      allow(mailer).to receive(:general_notification).with(
        channel: "monitoring",
        message: "System is healthy"
      ).and_return(mail_message)

      notifier.send_message("monitoring", "System is healthy")

      expect(mailer).to have_received(:general_notification)
      expect(mail_message).to have_received(:deliver_now)
    end
  end
end
